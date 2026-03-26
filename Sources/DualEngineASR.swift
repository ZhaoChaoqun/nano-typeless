import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "DualEngineASR")

/// 双引擎 ASR：Streaming Paraformer 实时预览 + QwenASR 流式精转写
///
/// 录音过程中：
/// - 前期（~2s）：Streaming Paraformer 流式处理音频，实时输出到 HUD（低延迟预览）
/// - QwenASR 同步接收相同音频流，持续增量推理
/// - QwenASR 产出首段文本后，自动切换 HUD 显示源为 QwenASR（含 unfixedText）
/// - 切换后 Paraformer 回调被忽略，但仍继续接收音频
///
/// 松开 Fn 后：
/// - QwenASR finalize 并输出最终结果（含标点）
///
/// 并发模型：
/// - `qwenQueue`（serial）：保护 QwenASR 引擎的所有调用（pushAudio / getResult / reset）
/// - `paraformerEngine` 使用自己内部的 `recognitionQueue`，完全独立
/// - `qwenHasOutput` 标志通过 os_unfair_lock 保护，确保跨队列安全读写
class DualEngineASR: ASREngine {

    // MARK: - Constants

    /// 结束时推送的最小静音样本数（0.1s × 16kHz = 1600 samples）
    /// 用于刷新 QwenASR 尾部不足一个 chunk 的音频
    private static let flushSilenceSampleCount = 1600

    // MARK: - 子引擎

    private let paraformerEngine: StreamingParaformerEngine
    private let qwenRecognizer: QwenASRStreamRecognizer

    // MARK: - QwenASR 流式推理队列（serial，防止并发访问引擎）

    private let qwenQueue = DispatchQueue(label: "com.typeless.dualengine.qwen", qos: .userInitiated)

    // MARK: - HUD 切换状态

    /// QwenASR 是否已产出文本。一旦为 true，HUD 由 QwenASR 驱动，Paraformer 回调被忽略。
    /// 该标志只会从 false → true 单向转变（每次录音期间），在 reset()/flush() 中重置。
    /// 被 Paraformer 的 recognitionQueue 和 qwenQueue 两个队列读写，
    /// 使用 os_unfair_lock 保护以确保线程安全。
    private var _qwenHasOutput = false
    private var lock = os_unfair_lock_s()

    /// flush 进行中标志。设为 true 后，qwenQueue 中排队的 processAudio 块会立即跳过，
    /// 避免 flush 块被大量耗时的 Metal GPU 推理阻塞。
    private var _isFlushing = false

    let needsPunctuation = false
    let needsITN = true

    /// 线程安全读取 qwenHasOutput
    private var qwenHasOutput: Bool {
        get {
            os_unfair_lock_lock(&lock)
            let value = _qwenHasOutput
            os_unfair_lock_unlock(&lock)
            return value
        }
        set {
            os_unfair_lock_lock(&lock)
            _qwenHasOutput = newValue
            os_unfair_lock_unlock(&lock)
        }
    }

    /// 线程安全读写 isFlushing
    private var isFlushing: Bool {
        get {
            os_unfair_lock_lock(&lock)
            let value = _isFlushing
            os_unfair_lock_unlock(&lock)
            return value
        }
        set {
            os_unfair_lock_lock(&lock)
            _isFlushing = newValue
            os_unfair_lock_unlock(&lock)
        }
    }

    // MARK: - 初始化

    /// - Parameters:
    ///   - paraformerEngine: Streaming Paraformer 引擎（负责实时预览）
    ///   - qwenRecognizer: QwenASR 识别器（负责流式精转写）
    init(paraformerEngine: StreamingParaformerEngine,
         qwenRecognizer: QwenASRStreamRecognizer) {
        self.paraformerEngine = paraformerEngine
        self.qwenRecognizer = qwenRecognizer
        logger.info("DualEngineASR 初始化完成（流式模式）")
    }

    // MARK: - ASREngine 协议

    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void) {
        // 1. 转发给 Paraformer 做实时预览（QwenASR 接管后跳过回调）
        paraformerEngine.processAudio(samples: samples) { [weak self] text, unfixed in
            guard let self = self, !self.qwenHasOutput else { return }
            onPartialResult(text, unfixed)
        }

        // 2. 同步推送给 QwenASR 流式引擎，产出文本后接管 HUD
        qwenQueue.async { [weak self] in
            guard let self = self, !self.isFlushing else { return }
            _ = self.qwenRecognizer.pushAudio(samples: samples, finalize: false)

            let stableText = self.qwenRecognizer.getResult()
            let unfixedText = self.qwenRecognizer.getUnfixed()

            let hasContent = !stableText.isEmpty || !(unfixedText?.isEmpty ?? true)
            if hasContent {
                if !self.qwenHasOutput {
                    self.qwenHasOutput = true
                    logger.info("HUD 切换：QwenASR 已产出文本，接管 HUD 显示")
                }
                onPartialResult(stableText, unfixedText)
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        // 先设置 flushing 标志，让 qwenQueue 中排队的 processAudio 块立即跳过，
        // 避免 flush 块被大量耗时的 Metal GPU 推理阻塞
        isFlushing = true

        qwenQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // 推送极少量 silence（0.1s）+ finalize，让 Rust 处理尾部不足一个 chunk 的音频
            // 并 commit rollback 窗口内的 token
            let minimalSilence = [Float](repeating: 0.0, count: Self.flushSilenceSampleCount)
            _ = self.qwenRecognizer.pushAudio(samples: minimalSilence, finalize: true)

            let result = self.qwenRecognizer.getResult()
            self.qwenRecognizer.reset()

            // 重置标志，为下一次录音做准备
            self.qwenHasOutput = false
            self.isFlushing = false

            // 同步 reset Paraformer，防止下次录音 HUD 残留上次的累积文本
            self.paraformerEngine.reset()

            logger.info("Flush 完成: \(result.prefix(100), privacy: .public)")

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func reset() {
        qwenQueue.sync {
            _qwenHasOutput = false
            _isFlushing = false
            qwenRecognizer.reset()
        }
        paraformerEngine.reset()
    }
}
