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

        let recognizer = QwenASRStreamRecognizer(modelDir: tmpDir)
        XCTAssertNil(recognizer, "空目录（无模型文件）应返回 nil")
    }

    // MARK: - QwenASREngine + Mock 测试：processAudio 行为

    func testProcessAudioCallsPushAudio() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = "你好"
        mock.getResultText = "你好"

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)
        let samples = [Float](repeating: 0.1, count: 16000)

        let expectation = self.expectation(description: "recognition queue")
        engine.processAudio(samples: samples) { _ in
            XCTAssertEqual(mock.pushCallCount, 1, "pushAudio 应被调用一次")
            XCTAssertEqual(mock.receivedSamples.first?.count, 16000, "应传递 16000 个样本")
            XCTAssertEqual(mock.receivedFinalizeFlags.first, false, "finalize 应为 false")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testProcessAudioNilDeltaSkipsCallback() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil  // 无新增文本
        mock.getResultText = ""

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)

        var callbackInvoked = false
        engine.processAudio(samples: [Float](repeating: 0, count: 100)) { _ in
            callbackInvoked = true
        }

        let expectation = self.expectation(description: "wait for queue")
        queue.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(callbackInvoked,
                       "pushAudio 返回 nil 时不应触发 onPartialResult 回调")
    }

    // MARK: - QwenASREngine + Mock 测试：flush 行为

    func testFlushInjectsSilencePaddingAndFinalize() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = "最终结果"

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)

        let expectation = self.expectation(description: "flush")
        engine.flush { result in
            XCTAssertEqual(result, "最终结果")
            XCTAssertEqual(mock.receivedSamples.last?.count, 32000,
                           "flush 应注入 32000 样本的静音 padding")
            XCTAssertEqual(mock.receivedFinalizeFlags.last, true,
                           "flush 应发送 finalize=true")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testFlushCallsReset() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = "text"

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)

        let expectation = self.expectation(description: "reset after flush")
        engine.flush { _ in
            XCTAssertEqual(mock.resetCallCount, 1, "flush 后应调用 reset()")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testFlushReturnsEmptyWhenGetResultEmpty() {
        let mock = MockASRStreamRecognizer()
        mock.pushAudioResult = nil
        mock.getResultText = ""

        let queue = DispatchQueue(label: "test.recognition", qos: .userInitiated)
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)

        let expectation = self.expectation(description: "empty result")
        engine.flush { result in
            XCTAssertEqual(result, "", "getResult 为空时 flush 应返回空字符串")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
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
        let _: ASRStreamRecognizing.Type = QwenASRStreamRecognizer.self
    }

    // MARK: - RecordingManager 集成验证

    func testRecordingManagerTestableCreation() {
        let mockEngine = MockASREngine()
        let manager = RecordingManager.testable(withEngine: mockEngine)
        XCTAssertTrue(manager.isInitialized, "注入引擎后 isInitialized 应为 true")
    }

    func testRecordingManagerTestableWithNilEngine() {
        let manager = RecordingManager.testable(withEngine: nil)
        XCTAssertFalse(manager.isInitialized, "nil 引擎时 isInitialized 应为 false")
    }

    func testEngineNeedsPunctuationProperty() {
        let queue = DispatchQueue(label: "test.recognition")
        let mock = MockASRStreamRecognizer()
        let engine = QwenASREngine(recognizer: mock, recognitionQueue: queue)
        XCTAssertFalse(engine.needsPunctuation, "QwenASREngine 不需要外部标点处理")
    }
}
