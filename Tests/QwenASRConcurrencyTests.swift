import XCTest
@testable import Nano_Typeless

/// QwenASR 并发安全测试
class QwenASRConcurrencyTests: XCTestCase {

    static var modelAvailable = false

    override class func setUp() {
        super.setUp()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models/Qwen3-ASR-0.6B")
        modelAvailable = FileManager.default.fileExists(
            atPath: appSupport.appendingPathComponent("vocab.json").path)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.modelAvailable,
                          "Qwen3-ASR 模型不可用，跳过并发测试")
    }

    /// 快速交替 pushAudio/reset，验证不崩溃
    func testRapidResetDuringPush() throws {
        let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models/Qwen3-ASR-0.6B").path

        let recognizer = QwenASRStreamRecognizer(modelDir: modelDir)!
        let samples = [Float](repeating: 0.01, count: 16000)

        // 快速交替 push/reset 10 次
        for i in 0..<10 {
            _ = recognizer.pushAudio(samples: samples, finalize: false)
            recognizer.reset()
            print("[Concurrency] Cycle \(i + 1)/10 passed")
        }

        // 最终一次完整的 push + finalize
        _ = recognizer.pushAudio(samples: samples, finalize: true)
        let result = recognizer.getResult()
        print("[Concurrency] Final result after rapid reset: '\(result)'")
        // 不崩溃即为通过
    }

    /// 模拟 recognizer 在队列繁忙时被释放
    func testRecognizerDeinitWhileQueueBusy() throws {
        let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models/Qwen3-ASR-0.6B").path

        let queue = DispatchQueue(label: "test.concurrency", qos: .userInitiated)
        let expectation = self.expectation(description: "queue drained")

        var recognizer: QwenASRStreamRecognizer? = QwenASRStreamRecognizer(modelDir: modelDir)!
        let samples = [Float](repeating: 0.01, count: 16000)

        // 在队列中提交多个任务（强引用 recognizer）
        for _ in 0..<5 {
            let rec = recognizer!
            queue.async {
                _ = rec.pushAudio(samples: samples, finalize: false)
            }
        }

        // 立即释放 recognizer（但队列中的闭包仍持有强引用）
        recognizer = nil

        queue.async {
            // 到这里所有之前的 pushAudio 应该已完成
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
        print("[Concurrency] Recognizer deinit while queue busy: PASSED (no crash)")
    }

    /// 使用 Mock 测试 RecordingManager 的并发模式
    func testRecordingManagerRapidFlush() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = "text"
        mock.getResultText = "accumulated text"

        let manager = RecordingManager.testable(withQwenRecognizer: mock)

        // 快速提交多次 process + flush
        for _ in 0..<5 {
            manager.testableProcessWithQwenStreaming(
                samples: [Float](repeating: 0, count: 1600))
        }

        let expectation = self.expectation(description: "rapid flush")
        manager.testableFlushQwenStreaming { result in
            // 不崩溃且有结果即为通过
            XCTAssertFalse(result.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
