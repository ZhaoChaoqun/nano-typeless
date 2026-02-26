import Foundation

/// Mock ASR 流式识别器，用于单元测试
class MockASRStreamRecognizer: ASRStreamRecognizing {

    // MARK: - 可配置的返回值

    /// pushAudio 返回的 delta 文本（nil 表示无新增文本）
    var pushAudioResult: String? = nil
    /// getResult 返回的完整文本
    var getResultText: String = ""

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

    func reset() {
        resetCallCount += 1
    }
}
