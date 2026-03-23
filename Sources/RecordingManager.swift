import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "RecordingManager")

/// Thin coordinator that owns the FSM and delegates to focused subsystems:
/// - `AudioEngineManager` — microphone capture
/// - `PostProcessingPipeline` — ITN, punctuation, CSC, CloudRewrite
/// - `ASREngineFactory` — model loading and engine creation
///
/// Thread safety:
/// - All state transitions happen on `stateQueue` (serial).
/// - Audio processing runs on a Core Audio thread (via AudioEngineManager tap callback).
/// - Post-processing runs on `recognitionQueue` (via PostProcessingPipeline).
/// - UI callbacks are dispatched to the main queue.
class RecordingManager {
    static let shared = RecordingManager()

    private var currentEngine: (any ASREngine)?
    private let audioEngineManager = AudioEngineManager()
    private let postProcessingPipeline: PostProcessingPipeline

    /// 所有状态变更必须且只能通过此队列
    private let stateQueue = DispatchQueue(label: "com.typeless.state")
    private var state: RecordingState = .idle

    /// Recording session start time for analytics duration tracking
    private var sessionStartTime: ContinuousClock.Instant?

    /// 计算密集型操作的队列（ASR decoding + post-processing 共用）
    private let recognitionQueue = DispatchQueue(label: "com.typeless.recognition", qos: .userInitiated)

    /// 当前选择的 ASR 模型
    private(set) var currentModel: ASRModelType {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "selectedASRModel"),
               let model = ASRModelType(rawValue: rawValue) {
                return model
            }
            return .streamingParaformer
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedASRModel")
        }
    }

    // MARK: - 公开回调（由 TypelessApp 一次性注册）

    /// 部分识别结果回调（stableText, unfixedText）
    var onPartialResult: ((String, String?) -> Void)?
    /// 实时音频电平回调（0.0 ~ 1.0）
    var onAudioLevel: ((Float) -> Void)? {
        didSet { audioEngineManager.onAudioLevel = onAudioLevel }
    }
    /// 最终识别结果回调（替代旧的 stopRecording completion）
    var onFinalResult: ((String?) -> Void)?
    /// 录音开始时回调（用于显示 overlay）
    var onRecordingStarted: (() -> Void)?
    /// 进入处理阶段时回调（用于显示 processing 状态）
    var onProcessingStarted: (() -> Void)?

    init() {
        self.postProcessingPipeline = PostProcessingPipeline(processingQueue: recognitionQueue)

        // 单元测试环境下跳过自动模型加载
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            logger.info("检测到单元测试环境，跳过自动模型加载")
            return
        }
        handleEvent(.reloadRequested)
    }

    // MARK: - 公开事件入口

    /// 唯一的公开事件入口，驱动 FSM 状态转换
    func handleEvent(_ event: RecordingEvent) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            let oldState = self.state

            guard let newState = RecordingState.nextState(from: oldState, event: event) else {
                // 非法/被忽略的事件
                switch event {
                case .fnKeyDown, .fnKeyUp:
                    logger.debug("事件 \(event, privacy: .public) 在状态 \(oldState, privacy: .public) 下被忽略")
                default:
                    break
                }
                return
            }

            self.state = newState
            if oldState.description != newState.description {
                logger.debug("状态转换: \(oldState, privacy: .public) → \(newState, privacy: .public) [事件: \(event, privacy: .public)]")
            }
            self.handleSideEffects(from: oldState, to: newState, event: event)
        }
    }

    /// 切换 ASR 模型
    func switchModel(to model: ASRModelType) async {
        await initializeRecognizer()
    }

    var isInitialized: Bool {
        currentEngine != nil
    }

    /// 重新加载模型（下载完成后调用）
    func reloadModel() {
        handleEvent(.reloadRequested)
    }

    // MARK: - 副作用处理（在 stateQueue 上调用）

    private func handleSideEffects(from oldState: RecordingState, to newState: RecordingState, event: RecordingEvent) {
        switch (oldState, newState) {

        // 开始初始化模型
        case (_, .initializing):
            currentEngine = nil
            Task { await self.initializeRecognizer() }

        // 开始录音
        case (.ready, .recording):
            self.sessionStartTime = .now
            DispatchQueue.main.async { self.onRecordingStarted?() }
            self.startRecording()

        // 部分识别结果
        case (.recording, .recording):
            if case .partialResult(let text, let unfixedText) = event {
                DispatchQueue.main.async { self.onPartialResult?(text, unfixedText) }
            }

        // 停止录音，开始 flush
        case (.recording, .flushing(let accText)):
            DispatchQueue.main.async { self.onProcessingStarted?() }
            self.audioEngineManager.stop()
            self.flushEngine(fallbackText: accText)

        // flush 完成，开始后处理
        case (.flushing, .postProcessing(let rawText)):
            self.postProcessingPipeline.process(rawText: rawText, engine: self.currentEngine) { [weak self] finalText in
                self?.handleEvent(.postProcessComplete(finalText: finalText))
            }

        // 后处理完成
        case (.postProcessing, .ready):
            if case .postProcessComplete(let finalText) = event {
                // Analytics: track completed session
                if let startTime = self.sessionStartTime {
                    let elapsed = startTime.duration(to: .now)
                    let durationSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    AnalyticsService.track("Session.Completed", parameters: [
                        "engine": self.currentModel.rawValue,
                        "durationBucket": AnalyticsService.durationBucket(seconds: durationSeconds),
                        "hasResult": "\(finalText != nil && !(finalText?.isEmpty ?? true))",
                        "resultLengthBucket": AnalyticsService.lengthBucket(count: finalText?.count ?? 0),
                    ])
                    self.sessionStartTime = nil
                }
                DispatchQueue.main.async { self.onFinalResult?(finalText) }
            }

        default:
            break
        }
    }

    // MARK: - Recording Lifecycle

    /// Starts audio capture and wires samples to the ASR engine.
    /// Called from stateQueue.
    private func startRecording() {
        audioEngineManager.onSamples = { [weak self] samples in
            self?.processAudioSamples(samples)
        }
        audioEngineManager.start()
        logger.info("开始流式录音 (\(self.currentModel.displayName, privacy: .public))")
    }

    /// Processes audio samples: state check + forward to ASR engine.
    /// Called from Core Audio thread (via AudioEngineManager tap callback).
    private func processAudioSamples(_ samples: [Float]) {
        // Lightweight state check: only process audio in recording state
        guard stateQueue.sync(execute: { state.isRecording }) else { return }

        // Forward to ASR engine
        currentEngine?.processAudio(samples: samples) { [weak self] stableText, unfixedText in
            self?.handleEvent(.partialResult(text: stableText, unfixedText: unfixedText))
        }
    }

    // MARK: - Flush

    private func flushEngine(fallbackText: String) {
        guard let engine = currentEngine else {
            handleEvent(.flushComplete(rawText: ""))
            return
        }

        let flushStart = ContinuousClock.now
        engine.flush { [weak self] rawText in
            guard let self = self else { return }
            let flushMs = AnalyticsService.elapsedMs(since: flushStart)
            let text = rawText.isEmpty ? fallbackText : rawText
            AnalyticsService.track("ASR.FlushCompleted", parameters: [
                "engine": self.currentModel.rawValue,
                "latencyMs": "\(flushMs)",
                "success": "\(!rawText.isEmpty)",
                "rawTextLengthBucket": AnalyticsService.lengthBucket(count: text.count),
            ])
            self.handleEvent(.flushComplete(rawText: text))
        }
    }

    // MARK: - 模型加载

    private func initializeRecognizer() async {
        // Release old engine and drain recognitionQueue to prevent closures holding stale references
        currentEngine = nil
        recognitionQueue.sync {}

        let result = await ASREngineFactory.createEngine(
            for: currentModel,
            pipeline: postProcessingPipeline,
            recognitionQueue: recognitionQueue
        )

        currentEngine = result.engine

        if currentEngine != nil {
            handleEvent(.modelLoaded)
        } else {
            handleEvent(.modelLoadFailed)
        }
    }

    // MARK: - Test Support

    #if DEBUG
    /// 创建可测试的实例（注入 Mock 引擎）
    static func testable(withEngine engine: (any ASREngine)?) -> RecordingManager {
        let manager = RecordingManager()
        manager.currentEngine = engine
        if engine != nil {
            manager.stateQueue.sync { manager.state = .ready }
        }
        return manager
    }

    /// 暴露给测试的当前状态
    var testableState: RecordingState {
        get { stateQueue.sync { state } }
        set { stateQueue.sync { state = newValue } }
    }
    #endif
}
