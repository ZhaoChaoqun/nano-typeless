import XCTest
@testable import Nano_Typeless

/// QwenASR 并发安全测试
class QwenASRConcurrencyTests: XCTestCase {

    static var modelAvailable = false

    override class func setUp() {
        super.setUp()
        modelAvailable = TestEnvironment.isModelAvailable
    }

    // MARK: - 需要真实模型的并发测试

    /// 快速交替 pushAudio/reset，验证不崩溃
    func testRapidResetDuringPush() throws {
        try XCTSkipUnless(Self.modelAvailable,
                          "Qwen3-ASR 模型不可用，跳过并发测试")

        let modelDir = TestEnvironment.qwenModelDirectory()!
        let recognizer = QwenASRStreamRecognizer(modelDir: modelDir)!
        let samples = [Float](repeating: 0.01, count: 16000)

        for _ in 0..<10 {
            _ = recognizer.pushAudio(samples: samples, finalize: false)
            recognizer.reset()
        }

        _ = recognizer.pushAudio(samples: samples, finalize: true)
        let result = recognizer.getResult()
        // 不崩溃即为通过
        _ = result
    }

    /// 模拟 recognizer 在队列繁忙时被释放
    func testRecognizerDeinitWhileQueueBusy() throws {
        try XCTSkipUnless(Self.modelAvailable,
                          "Qwen3-ASR 模型不可用，跳过并发测试")

        let modelDir = TestEnvironment.qwenModelDirectory()!

        let queue = DispatchQueue(label: "test.concurrency", qos: .userInitiated)
        let expectation = self.expectation(description: "queue drained")

        var recognizer: QwenASRStreamRecognizer? = QwenASRStreamRecognizer(modelDir: modelDir)!
        let samples = [Float](repeating: 0.01, count: 16000)

        for _ in 0..<5 {
            let rec = recognizer!
            queue.async {
                _ = rec.pushAudio(samples: samples, finalize: false)
            }
        }

        recognizer = nil

        queue.async {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Mock 测试：QwenASREngine 并发

    /// 使用 Mock 快速交替 processAudio + flush
    func testEngineRapidProcessAndFlush() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = "text"
        mock.getResultText = "accumulated text"

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)

        for _ in 0..<5 {
            engine.processAudio(samples: [Float](repeating: 0, count: 1600)) { _ in }
        }

        let expectation = self.expectation(description: "rapid flush")
        engine.flush { result in
            XCTAssertFalse(result.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    /// 使用 MockASREngine 验证 RecordingManager 创建不崩溃
    func testRecordingManagerWithMockEngine() {
        let mockEngine = MockASREngine()
        mockEngine.flushResult = "accumulated text"
        mockEngine.partialResultText = "partial"

        let manager = RecordingManager.testable(withEngine: mockEngine)
        XCTAssertTrue(manager.isInitialized)

        // 直接测试引擎的 flush
        let expectation = self.expectation(description: "engine flush")
        mockEngine.flush { result in
            XCTAssertEqual(result, "accumulated text")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
