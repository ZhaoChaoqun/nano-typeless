import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "ASREngineFactory")

/// Creates and initializes ASR engine instances based on the selected model type.
///
/// Encapsulates all model-loading logic (Streaming Paraformer, QwenASR, Dual Engine)
/// and their supporting models (punctuation, CSC, ITN).
///
/// Thread safety:
/// - `createEngine(for:pipeline:recognitionQueue:)` is async and called from a Task
///   spawned on stateQueue. It writes to `pipeline` properties which are safe because
///   no other code touches them during initialization (FSM is in `.initializing` state).
enum ASREngineFactory {

    /// Result of engine creation.
    struct Result {
        let engine: (any ASREngine)?
    }

    /// Creates an ASR engine for the given model type, also loading supporting models
    /// (punctuation, CSC, ITN, TermNormalizer) into the provided pipeline.
    ///
    /// - Parameters:
    ///   - modelType: Which ASR model to load.
    ///   - pipeline: The post-processing pipeline to configure with supporting models.
    ///   - recognitionQueue: The serial queue used by the ASR engine for decoding.
    /// - Returns: The created ASR engine (nil on failure).
    static func createEngine(
        for modelType: ASRModelType,
        pipeline: PostProcessingPipeline,
        recognitionQueue: DispatchQueue
    ) async -> Result {
        logger.info("开始加载语音识别模型 (\(modelType.displayName, privacy: .public))")
        let loadStart = ContinuousClock.now

        // Clear previous pipeline state
        pipeline.reset()

        var engine: (any ASREngine)?

        switch modelType {
        case .streamingParaformer:
            engine = await createStreamingParaformer(pipeline: pipeline, recognitionQueue: recognitionQueue)
        case .qwenASR:
            engine = await createQwenASR(pipeline: pipeline, recognitionQueue: recognitionQueue)
        case .dualEngine:
            engine = await createDualEngine(pipeline: pipeline, recognitionQueue: recognitionQueue)
        }

        // Load TermNormalizer (shared by all engines)
        let termNormalizer = TermNormalizer()
        if termNormalizer != nil {
            logger.info("TermNormalizer 词典加载成功")
        } else {
            logger.warning("TermNormalizer 词典加载失败，跳过专有名词标准化")
        }
        pipeline.termNormalizer = termNormalizer

        // Analytics: track model load result
        let loadMs = AnalyticsService.elapsedMs(since: loadStart)
        let success = engine != nil
        var params: [String: String] = [
            "engine": modelType.rawValue,
            "success": "\(success)",
        ]
        if !success {
            params["errorType"] = "load_failed"
        }
        AnalyticsService.track("Model.LoadCompleted", parameters: params, floatValue: Double(loadMs))

        return Result(engine: engine)
    }

    // MARK: - Streaming Paraformer

    private static func createStreamingParaformer(
        pipeline: PostProcessingPipeline,
        recognitionQueue: DispatchQueue
    ) async -> (any ASREngine)? {
        guard SherpaOnnxManager.shared.isStreamingParaformerDownloaded(),
              let paths = SherpaOnnxManager.shared.getStreamingParaformerPath() else {
            logger.warning("Streaming Paraformer 模型未下载")
            return nil
        }

        let itnFstPath = await loadITNFst()

        guard let recognizer = SherpaOnnxOnlineRecognizer(
            encoderPath: paths.encoderPath,
            decoderPath: paths.decoderPath,
            tokensPath: paths.tokensPath,
            ruleFstsPath: itnFstPath
        ) else {
            logger.error("Streaming Paraformer 模型加载失败")
            return nil
        }

        let engine = StreamingParaformerEngine(
            recognizer: recognizer, recognitionQueue: recognitionQueue
        )
        logger.info("Streaming Paraformer 模型加载成功")

        // Load CSC + punctuation post-processing modules
        await loadPunctuation(into: pipeline)
        loadCSC(into: pipeline)

        return engine
    }

    // MARK: - QwenASR

    private static func createQwenASR(
        pipeline: PostProcessingPipeline,
        recognitionQueue: DispatchQueue
    ) async -> (any ASREngine)? {
        guard SherpaOnnxManager.shared.isQwenASRModelDownloaded(),
              let modelDir = SherpaOnnxManager.shared.getQwenASRModelDir() else {
            logger.warning("QwenASR 模型未下载")
            return nil
        }

        guard let recognizer = QwenASRStreamRecognizer(modelDir: modelDir) else {
            logger.error("QwenASR 流式模型加载失败")
            return nil
        }

        let engine = QwenASREngine(
            recognizer: recognizer, recognitionQueue: recognitionQueue
        )
        logger.info("QwenASR 流式模型加载成功")

        // Load standalone ITN for post-processing
        if let itnFstPath = await loadITNFst() {
            pipeline.itn = SherpaOnnxITN(ruleFsts: itnFstPath)
            if pipeline.itn != nil {
                logger.info("ITN 模型加载成功")
            } else {
                logger.warning("ITN 模型初始化失败")
            }
        }

        return engine
    }

    // MARK: - Dual Engine

    private static func createDualEngine(
        pipeline: PostProcessingPipeline,
        recognitionQueue: DispatchQueue
    ) async -> (any ASREngine)? {
        // 1. Load Streaming Paraformer
        guard SherpaOnnxManager.shared.isStreamingParaformerDownloaded(),
              let paths = SherpaOnnxManager.shared.getStreamingParaformerPath() else {
            logger.warning("Dual Engine: Streaming Paraformer 模型未下载")
            return nil
        }

        let itnFstPath = await loadITNFst()

        guard let parafoRecognizer = SherpaOnnxOnlineRecognizer(
            encoderPath: paths.encoderPath,
            decoderPath: paths.decoderPath,
            tokensPath: paths.tokensPath,
            ruleFstsPath: itnFstPath
        ) else {
            logger.error("Dual Engine: Streaming Paraformer 模型加载失败")
            return nil
        }

        let paraformerEngine = StreamingParaformerEngine(
            recognizer: parafoRecognizer, recognitionQueue: recognitionQueue
        )
        logger.info("Dual Engine: Streaming Paraformer 加载成功")

        // 2. Load QwenASR (for offline precise transcription)
        guard SherpaOnnxManager.shared.isQwenASRModelDownloaded(),
              let modelDir = SherpaOnnxManager.shared.getQwenASRModelDir() else {
            logger.warning("Dual Engine: QwenASR 模型未下载")
            return nil
        }

        guard let qwenRecognizer = QwenASRStreamRecognizer(modelDir: modelDir) else {
            logger.error("Dual Engine: QwenASR 模型加载失败")
            return nil
        }
        logger.info("Dual Engine: QwenASR 加载成功")

        // 3. Create dual engine
        let engine = DualEngineASR(
            paraformerEngine: paraformerEngine,
            qwenRecognizer: qwenRecognizer
        )
        logger.info("Dual Engine: 初始化完成")

        // 4. Load standalone ITN for post-processing
        if let itnFstPathForPostProcess = await loadITNFst() {
            pipeline.itn = SherpaOnnxITN(ruleFsts: itnFstPathForPostProcess)
            if pipeline.itn != nil {
                logger.info("Dual Engine: ITN 模型加载成功")
            }
        }

        return engine
    }

    // MARK: - Supporting Model Loaders

    private static func loadPunctuation(into pipeline: PostProcessingPipeline) async {
        if let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
            pipeline.punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
            if pipeline.punctuator != nil {
                logger.info("标点模型加载成功")
            }
        } else {
            logger.info("标点模型未下载，正在下载...")
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadPunctuationModel(progress: { progress in
                    logger.debug("标点模型下载: \(progress, privacy: .public)")
                }, completion: { success, error in
                    if success, let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
                        pipeline.punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
                        logger.info("标点模型下载并加载成功")
                    } else {
                        logger.error("标点模型下载失败: \(error ?? "未知错误", privacy: .public)")
                    }
                    continuation.resume()
                })
            }
        }
    }

    private static func loadCSC(into pipeline: PostProcessingPipeline) {
        if let paths = SherpaOnnxManager.shared.getCSCModelPath() {
            pipeline.corrector = ChineseSpellingCorrector(modelPath: paths.modelPath, vocabPath: paths.vocabPath)
            if pipeline.corrector != nil {
                logger.info("CSC 纠错模型加载成功")
            } else {
                logger.warning("CSC 纠错模型加载失败")
            }
        } else {
            logger.info("CSC 纠错模型未下载，跳过")
        }
    }

    private static func loadITNFst() async -> String? {
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
}
