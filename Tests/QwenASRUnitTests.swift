import XCTest
@testable import Nano_Typeless

/// QwenASR 流式识别器的单元测试
/// 这些测试使用 Mock 识别器，不需要加载真实模型
class QwenASRUnitTests: XCTestCase {

    // MARK: - QwenASRStreamRecognizer init 安全性

    func testInitReturnsNilForNonexistentPath() {
        let recognizer = QwenASRStreamRecognizer(modelDir: "/nonexistent/path/to/model")
        XCTAssertNil(recognizer, "不存在的路径应返回 nil")
    }

    func testInitReturnsNilForEmptyDirectory() throws {
        let tmpDir = NSTemporaryDirectory() + "empty_model_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // 目录存在但缺少模型文件，qwen_asr_load_model 应返回 NULL
        let recognizer = QwenASRStreamRecognizer(modelDir: tmpDir)
        XCTAssertNil(recognizer, "空目录（无模型文件）应返回 nil")
    }

    // MARK: - Mock 测试：processWithQwenStreaming 行为

    func testProcessWithQwenStreamingCallsPushAudio() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = "你好"
        mock.getResultText = "你好"

        let manager = RecordingManager.testable(withQwenRecognizer: mock)
        let samples = [Float](repeating: 0.1, count: 16000)
        manager.testableProcessWithQwenStreaming(samples: samples)

        let expectation = self.expectation(description: "recognition queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(mock.pushCallCount, 1, "pushAudio 应被调用一次")
            XCTAssertEqual(mock.receivedSamples.first?.count, 16000, "应传递 16000 个样本")
            XCTAssertEqual(mock.receivedFinalizeFlags.first, false, "finalize 应为 false")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testProcessWithQwenStreamingNilDeltaSkipsUpdate() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil  // 无新增文本
        mock.getResultText = ""

        let manager = RecordingManager.testable(withQwenRecognizer: mock)
        manager.testableAccumulatedText = "之前的文本"

        manager.testableProcessWithQwenStreaming(samples: [Float](repeating: 0, count: 100))

        let expectation = self.expectation(description: "skip update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(manager.testableAccumulatedText, "之前的文本",
                           "pushAudio 返回 nil 时不应更新 accumulatedText")
            XCTAssertEqual(mock.getResultCallCount, 0,
                           "pushAudio 返回 nil 时不应调用 getResult")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Mock 测试：flushQwenStreaming 行为

    func testFlushQwenStreamingInjectsSilencePadding() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = "最终结果"

        let manager = RecordingManager.testable(withQwenRecognizer: mock)

        let expectation = self.expectation(description: "flush")
        manager.testableFlushQwenStreaming { result in
            XCTAssertEqual(result, "最终结果")
            // 验证注入了 2 秒静音 padding（32000 样本 @ 16kHz）
            XCTAssertEqual(mock.receivedSamples.last?.count, 32000,
                           "flush 应注入 32000 样本的静音 padding")
            // 验证 finalize=true
            XCTAssertEqual(mock.receivedFinalizeFlags.last, true,
                           "flush 应发送 finalize=true")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testFlushQwenStreamingCallsReset() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = "text"

        let manager = RecordingManager.testable(withQwenRecognizer: mock)

        let expectation = self.expectation(description: "reset after flush")
        manager.testableFlushQwenStreaming { _ in
            XCTAssertEqual(mock.resetCallCount, 1, "flush 后应调用 reset()")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testFlushFromGetResultFallsBackToAccumulatedText() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = ""  // getResult 返回空

        let manager = RecordingManager.testable(withQwenRecognizer: mock)
        manager.testableAccumulatedText = "fallback 文本"

        let expectation = self.expectation(description: "fallback")
        manager.testableFlushQwenStreaming { result in
            XCTAssertEqual(result, "fallback 文本",
                           "getResult 为空时应 fallback 到 accumulatedText")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testFlushWithNilRecognizerReturnsEmpty() {
        let manager = RecordingManager.testable(withQwenRecognizer: nil)

        let expectation = self.expectation(description: "nil recognizer")
        manager.testableFlushQwenStreaming { result in
            XCTAssertEqual(result, "", "nil recognizer 应返回空字符串")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Mock 测试：reset 行为

    func testResetClearsStateOnMock() {
        let mock = MockASRStreamRecognizer()
        _ = mock.pushAudio(samples: [0.1, 0.2], finalize: false)
        _ = mock.pushAudio(samples: [0.3, 0.4], finalize: false)

        mock.reset()

        XCTAssertEqual(mock.resetCallCount, 1)
        XCTAssertEqual(mock.pushCallCount, 2, "reset 不应影响 push 计数")
    }

    // MARK: - Mock 测试：空音频

    func testPushAudioWithEmptyArray() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil

        let result = mock.pushAudio(samples: [], finalize: false)

        XCTAssertNil(result, "空音频应返回 nil")
        XCTAssertEqual(mock.receivedSamples.first?.count, 0)
    }

    // MARK: - Protocol 一致性

    func testQwenASRStreamRecognizerConformsToProtocol() {
        // 编译时检查：QwenASRStreamRecognizer 遵循 ASRStreamRecognizing
        // 如果这行编译通过，说明 protocol 声明正确
        let _: ASRStreamRecognizing.Type = QwenASRStreamRecognizer.self
    }
}
