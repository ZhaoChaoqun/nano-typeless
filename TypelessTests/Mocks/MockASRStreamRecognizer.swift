import Foundation
@testable import Nano_Typeless

/// Mock ASR 流式识别器，用于单元测试 QwenASREngine
class MockASRStreamRecognizer: ASRStreamRecognizing {

    // MARK: - 可配置的返回值

    /// pushAudio 返回的 delta 文本（nil 表示无新增文本）
    var pushAudioResult: String? = nil
    /// getResult 返回的完整文本
    var getResultText: String = ""
    /// getUnfixed 返回的投机文本（nil 表示无 unfixed 文本）
    var getUnfixedText: String? = nil

    // MARK: - 调用记录

    var pushCallCount = 0
    var getResultCallCount = 0
    var resetCallCount = 0
    var receivedSamples: [[Float]] = []
    var receivedFinalizeFlags: [Bool] = []

    // MARK: - ASRStreamRecognizing

    func pushAudio(samples: [Float], finalize: Bool) -> String? {
        pushCallCount += 1
        receivedSamples.append(samples)
        receivedFinalizeFlags.append(finalize)
        return pushAudioResult
    }

    func getResult() -> String {
        getResultCallCount += 1
        return getResultText
    }

    func getUnfixed() -> String? {
        return getUnfixedText
    }

    func reset() {
        resetCallCount += 1
    }
}

/// Mock ASR 引擎，用于单元测试 RecordingManager
class MockASREngine: ASREngine {

    var needsPunctuation: Bool = false

    var processAudioCallCount = 0
    var flushCallCount = 0
    var resetCallCount = 0

    /// flush 时返回的文本
    var flushResult: String = ""
    /// processAudio 时回调的文本（nil 表示不回调）
    var partialResultText: String? = nil

    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void) {
        processAudioCallCount += 1
        if let text = partialResultText {
            onPartialResult(text, nil)
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        flushCallCount += 1
        DispatchQueue.main.async {
            completion(self.flushResult)
        }
    }

    func reset() {
        resetCallCount += 1
    }
}
