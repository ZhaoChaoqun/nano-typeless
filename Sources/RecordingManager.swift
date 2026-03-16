import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "RecordingManager")

/// Streaming Paraformer 后处理模式
enum PostProcessingMode: String, CaseIterable {
    case cscPunctuation = "csc_punctuation"
    case qwen3Rewrite = "qwen3_rewrite"
    case cloudRewrite = "cloud_rewrite"

    var displayName: String {
        switch self {
        case .cscPunctuation: return "CSC + 标点"
        case .qwen3Rewrite: return "Qwen3 Rewrite"
        case .cloudRewrite: return "Cloud Rewrite"
        }
    }

    var description: String {
        switch self {
        case .cscPunctuation: return "CSC 纠错 + CT-Transformer 标点（二阶段）"
        case .qwen3Rewrite: return "Qwen3-0.6B 一站式后处理（ITN + 标点 + CSC）"
        case .cloudRewrite: return "Cerebras Qwen3-32B 云端后处理（标点 + 纠错）"
        }
    }
}

/// 管理音频录制和语音识别（FSM 驱动）
class RecordingManager {
    static let shared = RecordingManager()

    private var audioEngine: AVAudioEngine?
    private var currentEngine: (any ASREngine)?
    private var punctuator: SherpaOnnxPunctuation?
    private var corrector: ChineseSpellingCorrector?
    private var rewriter: Qwen3TextRewriter?
    private var cloudRewriter: CloudRewriter?
    private var termNormalizer: TermNormalizer?
    private var itn: SherpaOnnxITN?

    /// 所有状态变更必须且只能通过此队列
    private let stateQueue = DispatchQueue(label: "com.typeless.state")
    private var state: RecordingState = .idle

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

    /// Streaming Paraformer 后处理模式
    var postProcessingMode: PostProcessingMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "postProcessingMode"),
               let mode = PostProcessingMode(rawValue: rawValue) {
                return mode
            }
            return .cscPunctuation
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "postProcessingMode")
        }
    }

    // MARK: - 公开回调（由 TypelessApp 一次性注册）

    /// 部分识别结果回调（stableText, unfixedText）
    var onPartialResult: ((String, String?) -> Void)?
    /// 实时音频电平回调（0.0 ~ 1.0）
    var onAudioLevel: ((Float) -> Void)?
    /// 最终识别结果回调（替代旧的 stopRecording completion）
    var onFinalResult: ((String?) -> Void)?
    /// 录音开始时回调（用于显示 overlay）
    var onRecordingStarted: (() -> Void)?
    /// 进入处理阶段时回调（用于显示 processing 状态）
    var onProcessingStarted: (() -> Void)?

    /// 计算密集型操作的队列
    private let recognitionQueue = DispatchQueue(label: "com.typeless.recognition", qos: .userInitiated)

    init() {
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
            DispatchQueue.main.async { self.onRecordingStarted?() }
            self.startAudioEngine()

        // 部分识别结果
        case (.recording, .recording):
            if case .partialResult(let text, let unfixedText) = event {
                DispatchQueue.main.async { self.onPartialResult?(text, unfixedText) }
            }

        // 停止录音，开始 flush
        case (.recording, .flushing(let accText)):
            DispatchQueue.main.async { self.onProcessingStarted?() }
            self.stopAudioEngine()
            self.flushEngine(fallbackText: accText)

        // flush 完成，开始后处理
        case (.flushing, .postProcessing(let rawText)):
            self.performPostProcessing(rawText: rawText)

        // 后处理完成
        case (.postProcessing, .ready):
            if case .postProcessComplete(let finalText) = event {
                DispatchQueue.main.async { self.onFinalResult?(finalText) }
            }

        default:
            break
        }
    }

    // MARK: - 音频引擎管理

    private func startAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            logger.error("无法创建目标音频格式")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            logger.error("无法创建音频转换器")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            let samples = self.extractSamples(buffer: buffer, converter: converter, targetFormat: targetFormat)
            if let samples = samples {
                self.processAudioSamples(samples)
            }
        }

        do {
            try audioEngine.start()
            logger.info("开始流式录音 (\(self.currentModel.displayName, privacy: .public))")
        } catch {
            logger.error("启动音频引擎失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        logger.info("停止录音")
    }

    /// 从 AVAudioPCMBuffer 提取 16kHz Float32 样本
    private func extractSamples(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Float]? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("音频转换错误: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let floatData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
    }

    /// 处理音频样本：计算电平 + 发送到 ASR 引擎
    /// 直接从 installTap 回调调用，绕过 stateQueue 以避免延迟
    private func processAudioSamples(_ samples: [Float]) {
        // 轻量状态检查：仅在 recording 状态处理音频
        guard stateQueue.sync(execute: { state.isRecording }) else { return }

        // 计算 RMS 音频电平并通知 UI
        if let onAudioLevel = onAudioLevel {
            var sum: Float = 0
            for s in samples { sum += s * s }
            let rms = sqrt(sum / max(Float(samples.count), 1))
            let db = 20 * log10(max(rms, 1e-6))
            let normalized = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async {
                onAudioLevel(normalized)
            }
        }

        // 通过引擎处理音频
        currentEngine?.processAudio(samples: samples) { [weak self] stableText, unfixedText in
            self?.handleEvent(.partialResult(text: stableText, unfixedText: unfixedText))
        }
    }

    // MARK: - Flush & Post-Processing

    private func flushEngine(fallbackText: String) {
        guard let engine = currentEngine else {
            handleEvent(.flushComplete(rawText: ""))
            return
        }

        engine.flush { [weak self] rawText in
            guard let self = self else { return }
            let text = rawText.isEmpty ? fallbackText : rawText
            self.handleEvent(.flushComplete(rawText: text))
        }
    }

    private func performPostProcessing(rawText: String) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }

            guard !rawText.isEmpty else {
                logger.info("最终识别结果: （无）")
                self.handleEvent(.postProcessComplete(finalText: nil))
                return
            }

            // 专有名词标准化（在所有后处理之前）
            let normalizedText = self.termNormalizer?.normalize(rawText) ?? rawText
            if normalizedText != rawText {
                logger.info("TermNormalizer: \(rawText, privacy: .public) → \(normalizedText, privacy: .public)")
            }

            // 对 Qwen3-ASR 等不需要标点处理的引擎，应用独立 ITN（逆文本规范化）
            var processedText = normalizedText
            if let engine = self.currentEngine, !engine.needsPunctuation, let itn = self.itn {
                processedText = itn.normalize(text: processedText)
                if processedText != normalizedText {
                    logger.info("ITN: \(normalizedText, privacy: .public) → \(processedText, privacy: .public)")
                }
            }

            guard let engine = self.currentEngine, engine.needsPunctuation else {
                logger.info("最终结果: \(processedText, privacy: .public)")
                self.handleEvent(.postProcessComplete(finalText: processedText))
                return
            }

            let finalText: String
            switch self.postProcessingMode {
            case .qwen3Rewrite:
                if let rewriter = self.rewriter {
                    logger.info("使用 Qwen3 Rewrite 后处理")
                    let rewritten = rewriter.rewrite(text: normalizedText)
                    logger.info("原始文本: \(normalizedText, privacy: .public)")
                    logger.info("Rewrite 后: \(rewritten, privacy: .public)")
                    finalText = rewritten
                } else {
                    logger.warning("Qwen3 Rewriter 未加载，回退到 CSC + 标点模式")
                    let correctedText = self.corrector?.correctSpelling(normalizedText) ?? normalizedText
                    finalText = self.punctuator?.addPunctuation(text: correctedText) ?? correctedText
                }
            case .cloudRewrite:
                if let cloudRewriter = self.cloudRewriter {
                    logger.info("使用 Cloud Rewrite 后处理")
                    logger.info("原始文本: \(normalizedText, privacy: .public)")
                    let semaphore = DispatchSemaphore(value: 0)
                    var rewritten = normalizedText
                    Task {
                        rewritten = await cloudRewriter.rewrite(text: normalizedText)
                        semaphore.signal()
                    }
                    semaphore.wait()
                    logger.info("Cloud Rewrite 后: \(rewritten, privacy: .public)")
                    finalText = rewritten
                } else {
                    logger.warning("CloudRewriter 未初始化，回退到 CSC + 标点模式")
                    let correctedText = self.corrector?.correctSpelling(normalizedText) ?? normalizedText
                    finalText = self.punctuator?.addPunctuation(text: correctedText) ?? correctedText
                }
            case .cscPunctuation:
                let correctedText = self.corrector?.correctSpelling(normalizedText) ?? normalizedText
                finalText = self.punctuator?.addPunctuation(text: correctedText) ?? correctedText
                logger.info("原始文本: \(normalizedText, privacy: .public)")
                if correctedText != normalizedText {
                    logger.info("CSC 纠正: \(correctedText, privacy: .public)")
                } else {
                    logger.info("CSC 未修改文本")
                }
                logger.info("标点处理后: \(finalText, privacy: .public)")
            }
            self.handleEvent(.postProcessComplete(finalText: finalText))
        }
    }

    // MARK: - 模型加载（保留 async/await）

    private func initializeRecognizer() async {
        logger.info("开始加载语音识别模型 (\(self.currentModel.displayName, privacy: .public))")

        // 释放旧引擎和附属模型，等待 recognitionQueue 排空防止闭包延迟持有旧引擎
        currentEngine = nil
        punctuator = nil
        corrector = nil
        rewriter = nil
        cloudRewriter = nil
        termNormalizer = nil
        itn = nil
        recognitionQueue.sync {}

        switch currentModel {
        case .streamingParaformer:
            await initializeStreamingParaformer()
        case .qwenASR:
            await initializeQwenASR()
        }

        // 加载专有名词词典（所有引擎共用）
        termNormalizer = TermNormalizer()
        if termNormalizer != nil {
            logger.info("TermNormalizer 词典加载成功")
        } else {
            logger.warning("TermNormalizer 词典加载失败，跳过专有名词标准化")
        }

        if currentEngine != nil {
            handleEvent(.modelLoaded)
        } else {
            handleEvent(.modelLoadFailed)
        }
    }

    private func initializeStreamingParaformer() async {
        guard SherpaOnnxManager.shared.isStreamingParaformerDownloaded(),
              let paths = SherpaOnnxManager.shared.getStreamingParaformerPath() else {
            logger.warning("Streaming Paraformer 模型未下载")
            return
        }

        let itnFstPath = await loadITNFst()

        guard let recognizer = SherpaOnnxOnlineRecognizer(
            encoderPath: paths.encoderPath,
            decoderPath: paths.decoderPath,
            tokensPath: paths.tokensPath,
            ruleFstsPath: itnFstPath
        ) else {
            logger.error("Streaming Paraformer 模型加载失败")
            return
        }

        currentEngine = StreamingParaformerEngine(
            recognizer: recognizer, recognitionQueue: recognitionQueue
        )
        logger.info("Streaming Paraformer 模型加载成功")

        // 根据后处理模式加载对应模块
        switch postProcessingMode {
        case .qwen3Rewrite:
            await initializeQwen3Rewriter()
            // 也加载 CSC + 标点作为回退
            await initializePunctuation()
            initializeCSC()
        case .cloudRewrite:
            cloudRewriter = CloudRewriter()
            // 也加载 CSC + 标点作为回退
            await initializePunctuation()
            initializeCSC()
        case .cscPunctuation:
            await initializePunctuation()
            initializeCSC()
        }
    }

    private func initializeQwenASR() async {
        guard SherpaOnnxManager.shared.isQwenASRModelDownloaded(),
              let modelDir = SherpaOnnxManager.shared.getQwenASRModelDir() else {
            logger.warning("QwenASR 模型未下载")
            return
        }

        guard let recognizer = QwenASRStreamRecognizer(modelDir: modelDir) else {
            logger.error("QwenASR 流式模型加载失败")
            return
        }

        currentEngine = QwenASREngine(
            recognizer: recognizer, recognitionQueue: recognitionQueue
        )
        logger.info("QwenASR 流式模型加载成功")

        // 加载独立 ITN（逆文本规范化），用于将中文数字读法转换为阿拉伯数字
        if let itnFstPath = await loadITNFst() {
            self.itn = SherpaOnnxITN(ruleFsts: itnFstPath)
            if self.itn != nil {
                logger.info("ITN 模型加载成功")
            } else {
                logger.warning("ITN 模型初始化失败")
            }
        }
    }

    private func initializePunctuation() async {
        if let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
            punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
            if punctuator != nil {
                logger.info("标点模型加载成功")
            }
        } else {
            logger.info("标点模型未下载，正在下载...")
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadPunctuationModel(progress: { progress in
                    logger.debug("标点模型下载: \(progress, privacy: .public)")
                }, completion: { [weak self] success, error in
                    if success, let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
                        self?.punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
                        logger.info("标点模型下载并加载成功")
                    } else {
                        logger.error("标点模型下载失败: \(error ?? "未知错误", privacy: .public)")
                    }
                    continuation.resume()
                })
            }
        }
    }

    private func initializeCSC() {
        if let paths = SherpaOnnxManager.shared.getCSCModelPath() {
            corrector = ChineseSpellingCorrector(modelPath: paths.modelPath, vocabPath: paths.vocabPath)
            if corrector != nil {
                logger.info("CSC 纠错模型加载成功")
            } else {
                logger.warning("CSC 纠错模型加载失败")
            }
        } else {
            logger.info("CSC 纠错模型未下载，跳过")
        }
    }

    private func initializeQwen3Rewriter() async {
        if let modelDir = SherpaOnnxManager.shared.getQwen3RewriteModelDir() {
            rewriter = Qwen3TextRewriter(modelDir: modelDir)
            if rewriter != nil {
                logger.info("Qwen3 Rewriter 模型加载成功")
            } else {
                logger.warning("Qwen3 Rewriter 模型加载失败")
            }
        } else {
            logger.info("Qwen3 Rewrite 模型未下载，正在下载...")
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadQwen3RewriteModel(progress: { progress in
                    logger.debug("Qwen3 Rewrite 模型下载: \(progress, privacy: .public)")
                }, completion: { [weak self] success, error in
                    if success, let modelDir = SherpaOnnxManager.shared.getQwen3RewriteModelDir() {
                        self?.rewriter = Qwen3TextRewriter(modelDir: modelDir)
                        logger.info("Qwen3 Rewrite 模型下载并加载成功")
                    } else {
                        logger.error("Qwen3 Rewrite 模型下载失败: \(error ?? "未知错误", privacy: .public)")
                    }
                    continuation.resume()
                })
            }
        }
    }

    private func loadVAD() async -> SherpaOnnxVAD? {
        if let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
            return SherpaOnnxVAD(modelPath: vadPath)
        }

        logger.info("VAD 模型未下载，正在下载...")
        return await withCheckedContinuation { continuation in
            SherpaOnnxManager.shared.downloadVADModel(progress: { progress in
                logger.debug("VAD 下载: \(progress, privacy: .public)")
            }, completion: { success, error in
                if success, let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
                    continuation.resume(returning: SherpaOnnxVAD(modelPath: vadPath))
                } else {
                    logger.error("VAD 下载失败: \(error ?? "未知错误", privacy: .public)")
                    continuation.resume(returning: nil)
                }
            })
        }
    }

    private func loadITNFst() async -> String? {
        if let fstPath = SherpaOnnxManager.shared.getITNFstPath() {
            return fstPath
        }

        logger.info("ITN FST 模型未下载，正在下载...")
        return await withCheckedContinuation { continuation in
            SherpaOnnxManager.shared.downloadITNFst(progress: { progress in
                logger.debug("ITN FST 下载: \(progress, privacy: .public)")
            }, completion: { success, error in
                if success, let fstPath = SherpaOnnxManager.shared.getITNFstPath() {
                    continuation.resume(returning: fstPath)
                } else {
                    logger.error("ITN FST 下载失败: \(error ?? "未知错误", privacy: .public)")
                    continuation.resume(returning: nil)
                }
            })
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
