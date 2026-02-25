import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "RecordingManager")

/// 管理音频录制和语音识别
class RecordingManager {
    static let shared = RecordingManager()

    private var audioEngine: AVAudioEngine?
    private var currentEngine: (any ASREngine)?
    private var punctuator: SherpaOnnxPunctuation?

    /// 用于保护共享可变状态的串行队列
    private let stateQueue = DispatchQueue(label: "com.typeless.state")
    private var _isRecording = false
    private var _isInitializing = false
    private var _accumulatedText: String = ""

    private var isRecording: Bool {
        get { stateQueue.sync { _isRecording } }
        set { stateQueue.sync { _isRecording = newValue } }
    }

    private var isInitializing: Bool {
        get { stateQueue.sync { _isInitializing } }
        set { stateQueue.sync { _isInitializing = newValue } }
    }

    /// 线程安全的累积文本访问
    private var accumulatedText: String {
        get { stateQueue.sync { _accumulatedText } }
        set { stateQueue.sync { _accumulatedText = newValue } }
    }

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

    /// 部分识别结果回调
    var onPartialResult: ((String) -> Void)?
    /// 实时音频电平回调（0.0 ~ 1.0）
    var onAudioLevel: ((Float) -> Void)?
    /// 用于识别的队列
    private let recognitionQueue = DispatchQueue(label: "com.typeless.recognition", qos: .userInitiated)

    init() {
        Task { await initializeRecognizer() }
    }

    /// 切换 ASR 模型
    func switchModel(to model: ASRModelType) async {
        await initializeRecognizer()
    }

    private func initializeRecognizer() async {
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        logger.info("开始加载语音识别模型 (\(self.currentModel.displayName))")

        // 清理旧的引擎
        currentEngine = nil

        switch currentModel {
        case .funasrNano:
            await initializeFunASR()
        case .streamingParaformer:
            await initializeStreamingParaformer()
        case .qwenASR:
            await initializeQwenASR()
        }
    }

    /// 初始化 FunASR Nano（需要 VAD）
    private func initializeFunASR() async {
        guard SherpaOnnxManager.shared.isFunASRModelDownloaded(),
              let paths = SherpaOnnxManager.shared.getFunASRModelPath() else {
            logger.warning("FunASR Nano 模型未下载")
            return
        }

        guard let recognizer = SherpaOnnxRecognizer(modelPath: paths.modelPath, tokensPath: paths.tokensPath) else {
            logger.error("FunASR Nano 模型加载失败")
            return
        }

        // 初始化 VAD（FunASR 需要）
        guard let vad = await loadVAD() else {
            logger.error("VAD 加载失败，FunASR 无法使用")
            return
        }

        currentEngine = FunASREngine(
            recognizer: recognizer, vad: vad,
            recognitionQueue: recognitionQueue, stateQueue: stateQueue
        )
        logger.info("FunASR Nano 模型加载成功")

        // 初始化标点处理器
        await initializePunctuation()
    }

    /// 初始化 Streaming Paraformer（无需 VAD）
    private func initializeStreamingParaformer() async {
        guard SherpaOnnxManager.shared.isStreamingParaformerDownloaded(),
              let paths = SherpaOnnxManager.shared.getStreamingParaformerPath() else {
            logger.warning("Streaming Paraformer 模型未下载")
            return
        }

        guard let recognizer = SherpaOnnxOnlineRecognizer(
            encoderPath: paths.encoderPath,
            decoderPath: paths.decoderPath,
            tokensPath: paths.tokensPath
        ) else {
            logger.error("Streaming Paraformer 模型加载失败")
            return
        }

        currentEngine = StreamingParaformerEngine(
            recognizer: recognizer, recognitionQueue: recognitionQueue
        )
        logger.info("Streaming Paraformer 模型加载成功")

        // 初始化标点处理器
        await initializePunctuation()
    }

    /// 初始化 QwenASR（流式模式，无需 VAD，不需要标点模型）
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
    }

    /// 初始化标点处理器
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
                    logger.debug("标点模型下载: \(progress)")
                }, completion: { [weak self] success, error in
                    if success, let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
                        self?.punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
                        logger.info("标点模型下载并加载成功")
                    } else {
                        logger.error("标点模型下载失败: \(error ?? "未知错误")")
                    }
                    continuation.resume()
                })
            }
        }
    }

    /// 加载 VAD 模型
    private func loadVAD() async -> SherpaOnnxVAD? {
        if let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
            return SherpaOnnxVAD(modelPath: vadPath)
        }

        logger.info("VAD 模型未下载，正在下载...")
        return await withCheckedContinuation { continuation in
            SherpaOnnxManager.shared.downloadVADModel(progress: { progress in
                logger.debug("VAD 下载: \(progress)")
            }, completion: { success, error in
                if success, let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
                    continuation.resume(returning: SherpaOnnxVAD(modelPath: vadPath))
                } else {
                    logger.error("VAD 下载失败: \(error ?? "未知错误")")
                    continuation.resume(returning: nil)
                }
            })
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        // 重置状态
        accumulatedText = ""
        currentEngine?.reset()

        // 创建音频引擎
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 目标格式：16kHz, mono, float32
        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            logger.error("无法创建目标音频格式")
            return
        }

        // 创建格式转换器
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            logger.error("无法创建音频转换器")
            return
        }

        // 安装音频 tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            isRecording = true
            logger.info("开始流式录音 (\(self.currentModel.displayName))")
        } catch {
            logger.error("启动音频引擎失败: \(error.localizedDescription)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // 计算输出缓冲区大小
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

        // 转换音频格式
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("音频转换错误: \(error.localizedDescription)")
            return
        }

        // 提取浮点样本
        guard let floatData = outputBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))

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

        // 统一通过引擎 protocol 处理音频
        currentEngine?.processAudio(samples: samples) { [weak self] text in
            guard let self = self else { return }
            self.accumulatedText = text
            DispatchQueue.main.async {
                self.onPartialResult?(text)
            }
        }
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        // 停止音频引擎
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        logger.info("停止录音")

        guard let engine = currentEngine else {
            completion(nil)
            return
        }

        engine.flush { [weak self] rawText in
            guard let self = self else {
                completion(nil)
                return
            }

            let text = rawText.isEmpty ? self.accumulatedText : rawText
            guard !text.isEmpty else {
                logger.info("最终识别结果: （无）")
                completion(nil)
                return
            }

            // 需要标点处理的引擎走标点后处理
            if engine.needsPunctuation {
                let finalText = self.punctuator?.addPunctuation(text: text) ?? text
                logger.info("原始文本: \(text)")
                logger.info("标点处理后: \(finalText)")
                completion(finalText)
            } else {
                logger.info("最终结果: \(text)")
                completion(text)
            }
        }
    }

    var isInitialized: Bool {
        currentEngine != nil
    }

    /// 重新加载模型（下载完成后调用）
    func reloadModel() {
        currentEngine = nil
        Task { await initializeRecognizer() }
    }

    // MARK: - Test Support

    #if DEBUG
    /// 创建可测试的实例（注入 Mock 引擎）
    static func testable(withEngine engine: (any ASREngine)?) -> RecordingManager {
        let manager = RecordingManager()
        manager.currentEngine = engine
        return manager
    }

    /// 暴露给测试的累积文本
    var testableAccumulatedText: String {
        get { accumulatedText }
        set { accumulatedText = newValue }
    }
    #endif
}
