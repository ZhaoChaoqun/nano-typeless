import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "DualEngineASR")

/// 双引擎 ASR：Streaming Paraformer 实时预览 + QwenASR 流式精转写
///
/// 录音过程中：
/// - Streaming Paraformer 流式处理音频，实时输出到 HUD
/// - QwenASR 同步接收相同音频流，持续增量推理
///
/// 松开 Fn 后：
/// - QwenASR finalize 并输出最终结果（含标点）
///
/// 并发模型：
/// - `qwenQueue`（serial）：保护 QwenASR 引擎的所有调用（pushAudio / getResult / reset）
/// - `paraformerEngine` 使用自己内部的 `recognitionQueue`，完全独立
class DualEngineASR: ASREngine {

    // MARK: - 子引擎

    private let paraformerEngine: StreamingParaformerEngine
    private let qwenRecognizer: QwenASRStreamRecognizer

    // MARK: - QwenASR 流式推理队列（serial，防止并发访问引擎）

    private let qwenQueue = DispatchQueue(label: "com.typeless.dualengine.qwen", qos: .userInitiated)

    let needsPunctuation = false

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
        // 1. 转发给 Paraformer 做实时预览
        paraformerEngine.processAudio(samples: samples, onPartialResult: onPartialResult)

        // 2. 同步推送给 QwenASR 流式引擎
        qwenQueue.async { [weak self] in
            guard let self = self else { return }
            _ = self.qwenRecognizer.pushAudio(samples: samples, finalize: false)
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        qwenQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // 推送极少量 silence（0.1s）+ finalize，让 Rust 处理尾部不足一个 chunk 的音频
            // 并 commit rollback 窗口内的 token
            let minimalSilence = [Float](repeating: 0.0, count: 1600)
            _ = self.qwenRecognizer.pushAudio(samples: minimalSilence, finalize: true)

            let result = self.qwenRecognizer.getResult()
            self.qwenRecognizer.reset()

            // 同步 reset Paraformer，防止下次录音 HUD 残留上次的累积文本
            self.paraformerEngine.reset()

            logger.info("Flush 完成: \(result.prefix(100), privacy: .public)")

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func reset() {
        paraformerEngine.reset()
        qwenQueue.sync {
            qwenRecognizer.reset()
        }
    }
}
