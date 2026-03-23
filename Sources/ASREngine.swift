import Foundation

/// 统一的 ASR 引擎接口
///
/// 封装了不同 ASR 后端（Streaming Paraformer、QwenASR）的差异，
/// 让 RecordingManager 无需关心具体引擎类型。
protocol ASREngine: AnyObject {
    /// 将新的音频采样送入引擎
    /// - Parameter samples: 16kHz monoFloat32 PCM 采样
    /// - Parameter onPartialResult: 有新的部分识别结果时回调（stableText, unfixedText）
    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void)

    /// 刷新引擎缓冲区，获取最终识别文本
    /// - Parameter completion: 返回最终文本（在 main queue 上调用）
    func flush(completion: @escaping (String) -> Void)

    /// 重置引擎状态，准备下一次识别
    func reset()

    /// 引擎是否需要外部标点处理
    var needsPunctuation: Bool { get }

    /// 引擎是否需要外部 ITN（逆文本规范化，如"一百二十三"→"123"）
    var needsITN: Bool { get }
}

// MARK: - Streaming Paraformer Engine

/// Streaming Paraformer 引擎：原生流式识别
class StreamingParaformerEngine: ASREngine {
    private let recognizer: SherpaOnnxOnlineRecognizer
    private let recognitionQueue: DispatchQueue

    let needsPunctuation = true
    let needsITN = false

    init(recognizer: SherpaOnnxOnlineRecognizer, recognitionQueue: DispatchQueue) {
        self.recognizer = recognizer
        self.recognitionQueue = recognitionQueue
    }

    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            self.recognizer.acceptWaveform(samples: samples)

            while self.recognizer.isReady() {
                self.recognizer.decode()
            }

            let text = self.recognizer.getResult()
            if !text.isEmpty {
                onPartialResult(text, nil)
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // is_final: 标记最终 chunk，启用短 chunk 接受 + CIF 尾部 token flush
            self.recognizer.setFinalChunk()
            self.recognizer.inputFinished()

            while self.recognizer.isReady() {
                self.recognizer.decode()
            }

            let text = self.recognizer.getResult()
            self.recognizer.reset()

            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    func reset() {
        recognizer.reset()
    }
}

// MARK: - QwenASR Streaming Engine

/// QwenASR 流式引擎：模拟流式（chunk + rollback）
class QwenASREngine: ASREngine {

    // MARK: - Constants

    /// 结束时推送的最小静音样本数（0.1s × 16kHz = 1600 samples）
    /// 用于刷新尾部不足一个 chunk 的音频，不会导致 decoder hallucinate
    private static let flushSilenceSampleCount = 1600

    // MARK: - Properties

    private let recognizer: ASRStreamRecognizing
    private let recognitionQueue: DispatchQueue

    let needsPunctuation = false
    let needsITN = true

    init(recognizer: ASRStreamRecognizing, recognitionQueue: DispatchQueue) {
        self.recognizer = recognizer
        self.recognitionQueue = recognitionQueue
    }

    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            _ = self.recognizer.pushAudio(samples: samples, finalize: false)

            // stable 确认文本
            let stableText = self.recognizer.getResult()

            // unfixed 投机文本（rollback 窗口 + unfixed chunks 中的 token）
            let unfixedText = self.recognizer.getUnfixed()

            let hasContent = !stableText.isEmpty || (unfixedText != nil && !unfixedText!.isEmpty)
            if hasContent {
                onPartialResult(stableText, unfixedText)
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // 推送极少量 silence（0.1s）+ finalize，让 Rust 处理尾部不足一个 chunk 的音频
            // 并 commit rollback 窗口内的 token。0.1s silence 不会导致 decoder hallucinate，
            // 而之前的 1s silence 在长音频上导致 decoder 重复之前的内容。
            let minimalSilence = [Float](repeating: 0.0, count: Self.flushSilenceSampleCount)
            _ = self.recognizer.pushAudio(samples: minimalSilence, finalize: true)

            let result = self.recognizer.getResult()
            self.recognizer.reset()

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func reset() {
        recognizer.reset()
    }
}
