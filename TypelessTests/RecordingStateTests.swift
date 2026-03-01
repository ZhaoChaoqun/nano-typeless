import XCTest
@testable import Nano_Typeless

final class RecordingStateTests: XCTestCase {

    // MARK: - 正常流程

    func testNormalRecordingFlow() {
        // idle → (reloadRequested) → initializing
        var state: RecordingState = .idle
        state = RecordingState.nextState(from: state, event: .reloadRequested)!
        XCTAssertEqual(state, .initializing)

        // initializing → (modelLoaded) → ready
        state = RecordingState.nextState(from: state, event: .modelLoaded)!
        XCTAssertEqual(state, .ready)

        // ready → (fnKeyDown) → recording("")
        state = RecordingState.nextState(from: state, event: .fnKeyDown)!
        XCTAssertEqual(state, .recording(accumulatedText: ""))

        // recording → (partialResult) → recording("你好")
        state = RecordingState.nextState(from: state, event: .partialResult(text: "你好"))!
        XCTAssertEqual(state, .recording(accumulatedText: "你好"))

        // recording → (fnKeyUp) → flushing("你好")
        state = RecordingState.nextState(from: state, event: .fnKeyUp)!
        XCTAssertEqual(state, .flushing(accumulatedText: "你好"))

        // flushing → (flushComplete) → postProcessing("你好世界")
        state = RecordingState.nextState(from: state, event: .flushComplete(rawText: "你好世界"))!
        XCTAssertEqual(state, .postProcessing(rawText: "你好世界"))

        // postProcessing → (postProcessComplete) → ready
        state = RecordingState.nextState(from: state, event: .postProcessComplete(finalText: "你好世界。"))!
        XCTAssertEqual(state, .ready)
    }

    // MARK: - 非法事件忽略

    func testFnKeyDownIgnoredInIdle() {
        let next = RecordingState.nextState(from: .idle, event: .fnKeyDown)
        XCTAssertNil(next, "idle 状态下 fnKeyDown 应被忽略")
    }

    func testFnKeyDownIgnoredInInitializing() {
        let next = RecordingState.nextState(from: .initializing, event: .fnKeyDown)
        XCTAssertNil(next, "initializing 状态下 fnKeyDown 应被忽略")
    }

    func testFnKeyUpIgnoredInReady() {
        let next = RecordingState.nextState(from: .ready, event: .fnKeyUp)
        XCTAssertNil(next, "ready 状态下 fnKeyUp 应被忽略")
    }

    func testFnKeyDownIgnoredInFlushing() {
        let next = RecordingState.nextState(from: .flushing(accumulatedText: "x"), event: .fnKeyDown)
        XCTAssertNil(next, "flushing 状态下 fnKeyDown 应被忽略")
    }

    func testFnKeyDownIgnoredInPostProcessing() {
        let next = RecordingState.nextState(from: .postProcessing(rawText: "x"), event: .fnKeyDown)
        XCTAssertNil(next, "postProcessing 状态下 fnKeyDown 应被忽略")
    }

    // MARK: - 模型加载

    func testModelLoadFailed() {
        let state: RecordingState = .initializing
        let next = RecordingState.nextState(from: state, event: .modelLoadFailed)
        XCTAssertEqual(next, .idle)
    }

    func testReloadFromReady() {
        let state: RecordingState = .ready
        let next = RecordingState.nextState(from: state, event: .reloadRequested)
        XCTAssertEqual(next, .initializing)
    }

    func testModelLoadedFromIdle() {
        // 当 init 时 handleEvent(.reloadRequested) 还没执行，但模型已经加载好了
        let next = RecordingState.nextState(from: .idle, event: .modelLoaded)
        XCTAssertEqual(next, .ready)
    }

    // MARK: - audioReceived 保持状态不变

    func testAudioReceivedKeepsRecordingState() {
        let state: RecordingState = .recording(accumulatedText: "你好")
        let next = RecordingState.nextState(from: state, event: .audioReceived(samples: [0.1, 0.2]))
        XCTAssertEqual(next, state, "audioReceived 不应改变状态")
    }

    // MARK: - flushing 保留 accumulatedText

    func testFlushingPreservesAccumulatedText() {
        let state: RecordingState = .recording(accumulatedText: "测试文本")
        let next = RecordingState.nextState(from: state, event: .fnKeyUp)
        XCTAssertEqual(next, .flushing(accumulatedText: "测试文本"))
    }

    // MARK: - Equatable

    func testRecordingStateEquatable() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertEqual(RecordingState.recording(accumulatedText: "a"), RecordingState.recording(accumulatedText: "a"))
        XCTAssertNotEqual(RecordingState.recording(accumulatedText: "a"), RecordingState.recording(accumulatedText: "b"))
        XCTAssertNotEqual(RecordingState.ready, RecordingState.idle)
    }

    // MARK: - Description

    func testRecordingStateDescription() {
        XCTAssertEqual(RecordingState.idle.description, "idle")
        XCTAssertEqual(RecordingState.initializing.description, "initializing")
        XCTAssertEqual(RecordingState.ready.description, "ready")
        XCTAssertEqual(RecordingState.recording(accumulatedText: "").description, "recording")
        XCTAssertEqual(RecordingState.flushing(accumulatedText: "").description, "flushing")
        XCTAssertEqual(RecordingState.postProcessing(rawText: "").description, "postProcessing")
    }
}
