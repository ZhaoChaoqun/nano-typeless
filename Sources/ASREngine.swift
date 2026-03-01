import Foundation

/// 统一的 ASR 引擎接口
///
/// 封装了不同 ASR 后端（SenseVoice Nano、Streaming Paraformer、QwenASR）的差异，
/// 让 RecordingManager 无需关心具体引擎类型。
protocol ASREngine: AnyObject {
    /// 将新的音频采样送入引擎
    /// - Parameter samples: 16kHz monoFloat32 PCM 采样
    /// - Parameter onPartialResult: 有新的部分识别结果时回调（在 recognitionQueue 上调用）
    func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void)

    /// 刷新引擎缓冲区，获取最终识别文本
    /// - Parameter completion: 返回最终文本（在 main queue 上调用）
    func flush(completion: @escaping (String) -> Void)

    /// 重置引擎状态，准备下一次识别
    func reset()

    /// 引擎是否需要外部标点处理
    var needsPunctuation: Bool { get }
}

// MARK: - SenseVoice Nano Engine (VAD + Offline)

/// SenseVoice Nano 引擎：使用 VAD 分段 + 离线识别
class FunASREngine: ASREngine {
    private let recognizer: SherpaOnnxRecognizer
    private let vad: SherpaOnnxVAD
    private let recognitionQueue: DispatchQueue
    private let internalQueue = DispatchQueue(label: "com.typeless.funasrengine")
    private var _accumulatedText = ""

    let needsPunctuation = true

    init(recognizer: SherpaOnnxRecognizer, vad: SherpaOnnxVAD,
         recognitionQueue: DispatchQueue) {
        self.recognizer = recognizer
        self.vad = vad
        self.recognitionQueue = recognitionQueue
    }

    func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void) {
        vad.acceptWaveform(samples: samples)

        while vad.hasSegment() {
            if let segment = vad.popSegmentWithTime() {
                recognitionQueue.async { [weak self] in
                    self?.transcribeSegment(segment, onPartialResult: onPartialResult)
                }
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        vad.flush()

        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            while self.vad.hasSegment() {
                if let segment = self.vad.popSegmentWithTime(),
                   let text = self.recognizer.transcribe(samples: segment.samples) {
                    self.internalQueue.sync {
                        self._accumulatedText += text
                    }
                }
            }

            let rawText = self.internalQueue.sync { self._accumulatedText }
            DispatchQueue.main.async {
                completion(rawText)
            }
        }
    }

    func reset() {
        vad.reset()
        internalQueue.sync { _accumulatedText = "" }
    }

    private func transcribeSegment(_ segment: SpeechSegment, onPartialResult: @escaping (String) -> Void) {
        if let text = recognizer.transcribe(samples: segment.samples) {
            let newAccumulated: String = internalQueue.sync {
                if _accumulatedText.isEmpty {
                    _accumulatedText = text
                } else {
                    _accumulatedText += text
                }
                return _accumulatedText
            }
            onPartialResult(newAccumulated)
        }
    }
}

// MARK: - Streaming Paraformer Engine

/// Streaming Paraformer 引擎：原生流式识别
class StreamingParaformerEngine: ASREngine {
    private let recognizer: SherpaOnnxOnlineRecognizer
    private let recognitionQueue: DispatchQueue

    let needsPunctuation = true

    init(recognizer: SherpaOnnxOnlineRecognizer, recognitionQueue: DispatchQueue) {
        self.recognizer = recognizer
        self.recognitionQueue = recognitionQueue
    }

    func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            self.recognizer.acceptWaveform(samples: samples)

            while self.recognizer.isReady() {
                self.recognizer.decode()
            }

            let text = self.recognizer.getResult()
            if !text.isEmpty {
                onPartialResult(text)
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            let silencePadding = [Float](repeating: 0.0, count: 4800)
            self.recognizer.acceptWaveform(samples: silencePadding)

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
    private let recognizer: ASRStreamRecognizing
    private let recognitionQueue: DispatchQueue

    let needsPunctuation = false

    init(recognizer: ASRStreamRecognizing, recognitionQueue: DispatchQueue) {
        self.recognizer = recognizer
        self.recognitionQueue = recognitionQueue
    }

    func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            _ = self.recognizer.pushAudio(samples: samples, finalize: false)
            let fullText = self.recognizer.getResult()
            if !fullText.isEmpty {
                onPartialResult(fullText)
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // finalize=true 刷出 rollback 区域的剩余 token，不需要额外静音 padding
            // （推送静音会被追加到累积 buffer，导致模型在静音段产生重复幻觉）
            _ = self.recognizer.pushAudio(samples: [], finalize: true)

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
