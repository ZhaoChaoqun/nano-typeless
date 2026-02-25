import Foundation
import AVFoundation

/// 管理音频录制和语音识别
class RecordingManager {
    static let shared = RecordingManager()

    private var audioEngine: AVAudioEngine?
    private var offlineRecognizer: SherpaOnnxRecognizer?       // FunASR Nano
    private var onlineRecognizer: SherpaOnnxOnlineRecognizer?  // Streaming Paraformer
    private var qwenStreamRecognizer: ASRStreamRecognizing?    // QwenASR (streaming)
    private var punctuator: SherpaOnnxPunctuation?             // 标点处理器
    private var vad: SherpaOnnxVAD?

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
        // 注意：不能用 currentModel 比较，因为 SettingsView 已经更新了 UserDefaults
        // 直接重新初始化识别器
        await initializeRecognizer()
    }

    private func initializeRecognizer() async {
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        print("========== 开始加载语音识别模型 (\(currentModel.displayName)) ==========")

        // 清理旧的识别器
        offlineRecognizer = nil
        onlineRecognizer = nil
        qwenStreamRecognizer = nil
        vad = nil

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
            print("⚠️ FunASR Nano 模型未下载")
            return
        }

        offlineRecognizer = SherpaOnnxRecognizer(modelPath: paths.modelPath, tokensPath: paths.tokensPath)

        if offlineRecognizer != nil {
            print("========== FunASR Nano 模型加载成功 ==========")
        } else {
            print("========== FunASR Nano 模型加载失败 ==========")
            return
        }

        // 初始化 VAD（FunASR 需要）
        await initializeVAD()

        // 初始化标点处理器
        await initializePunctuation()
    }

    /// 初始化 Streaming Paraformer（无需 VAD）
    private func initializeStreamingParaformer() async {
        guard SherpaOnnxManager.shared.isStreamingParaformerDownloaded(),
              let paths = SherpaOnnxManager.shared.getStreamingParaformerPath() else {
            print("⚠️ Streaming Paraformer 模型未下载")
            return
        }

        onlineRecognizer = SherpaOnnxOnlineRecognizer(
            encoderPath: paths.encoderPath,
            decoderPath: paths.decoderPath,
            tokensPath: paths.tokensPath
        )

        if onlineRecognizer != nil {
            print("========== Streaming Paraformer 模型加载成功 ==========")
        } else {
            print("========== Streaming Paraformer 模型加载失败 ==========")
        }

        // 初始化标点处理器
        await initializePunctuation()
    }

    /// 初始化 QwenASR（流式模式，无需 VAD，不需要标点模型）
    private func initializeQwenASR() async {
        guard SherpaOnnxManager.shared.isQwenASRModelDownloaded(),
              let modelDir = SherpaOnnxManager.shared.getQwenASRModelDir() else {
            print("⚠️ QwenASR 模型未下载")
            return
        }

        qwenStreamRecognizer = QwenASRStreamRecognizer(modelDir: modelDir)

        if qwenStreamRecognizer != nil {
            print("========== QwenASR 流式模型加载成功 ==========")
        } else {
            print("========== QwenASR 流式模型加载失败 ==========")
            return
        }
        // 流式模式无需 VAD 和标点模型
    }

    /// 初始化标点处理器
    private func initializePunctuation() async {
        // 先检查标点模型是否存在
        if let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
            punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
            if punctuator != nil {
                print("========== 标点模型加载成功 ==========")
            }
        } else {
            print("⚠️ 标点模型未下载，正在下载...")
            // 异步下载标点模型
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadPunctuationModel(progress: { progress in
                    print("[Punctuation] \(progress)")
                }, completion: { [weak self] success, error in
                    if success, let punctPath = SherpaOnnxManager.shared.getPunctuationModelPath() {
                        self?.punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
                        print("========== 标点模型下载并加载成功 ==========")
                    } else {
                        print("⚠️ 标点模型下载失败: \(error ?? "未知错误")")
                    }
                    continuation.resume()
                })
            }
        }
    }

    private func initializeVAD() async {
        // 先检查 VAD 模型是否存在
        if let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
            vad = SherpaOnnxVAD(modelPath: vadPath)
            if vad != nil {
                print("========== VAD 加载成功 ==========")
            }
        } else {
            print("⚠️ VAD 模型未下载，正在下载...")
            // 异步下载 VAD 模型
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadVADModel(progress: { progress in
                    print("[VAD] \(progress)")
                }, completion: { [weak self] success, error in
                    if success, let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
                        self?.vad = SherpaOnnxVAD(modelPath: vadPath)
                        print("========== VAD 下载并加载成功 ==========")
                    } else {
                        print("⚠️ VAD 下载失败: \(error ?? "未知错误")")
                    }
                    continuation.resume()
                })
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        // 重置状态
        accumulatedText = ""
        vad?.reset()
        qwenStreamRecognizer?.reset()

        // 创建音频引擎
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 目标格式：16kHz, mono, float32
        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            print("无法创建目标音频格式")
            return
        }

        // 创建格式转换器
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("无法创建音频转换器")
            return
        }

        // 安装音频 tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            isRecording = true
            print("开始流式录音 (\(currentModel.displayName))")
        } catch {
            print("启动音频引擎失败: \(error)")
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
            print("音频转换错误: \(error)")
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
            // 归一化到 0~1 范围（-60dB ~ 0dB 映射）
            let db = 20 * log10(max(rms, 1e-6))
            let normalized = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async {
                onAudioLevel(normalized)
            }
        }

        // 根据模型类型处理
        switch currentModel {
        case .funasrNano:
            processWithVAD(samples: samples)
        case .streamingParaformer:
            processWithStreaming(samples: samples)
        case .qwenASR:
            processWithQwenStreaming(samples: samples)
        }
    }

    /// 使用 VAD 分段处理（FunASR Nano）
    private func processWithVAD(samples: [Float]) {
        guard let vad = vad else { return }

        // 送入 VAD
        vad.acceptWaveform(samples: samples)

        // 检查是否有完整的语音段
        while vad.hasSegment() {
            if let segment = vad.popSegmentWithTime() {
                recognitionQueue.async { [weak self] in
                    self?.transcribeSegment(segment)
                }
            }
        }
    }

    /// 使用流式识别（Streaming Paraformer）
    private func processWithStreaming(samples: [Float]) {
        guard let recognizer = onlineRecognizer else { return }

        // 在识别队列中执行解码，避免阻塞 Core Audio 实时线程
        recognitionQueue.async { [weak self] in
            // 送入流式识别器
            recognizer.acceptWaveform(samples: samples)

            // 检查是否可以解码
            while recognizer.isReady() {
                recognizer.decode()
            }

            // 获取识别结果
            let text = recognizer.getResult()
            if !text.isEmpty {
                DispatchQueue.main.async {
                    self?.accumulatedText = text
                    self?.onPartialResult?(text)
                }
            }
        }
    }

    /// 使用流式识别（QwenASR Streaming）
    private func processWithQwenStreaming(samples: [Float]) {
        guard let recognizer = qwenStreamRecognizer else { return }

        // 在识别队列同步推送音频（stream_push_audio 内部跟踪 cursor，按 chunk 处理）
        recognitionQueue.async { [weak self] in
            if let delta = recognizer.pushAudio(samples: samples, finalize: false) {
                let fullText = recognizer.getResult()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // 使用 getResult() 获得完整文本，避免 delta 拼接时的 UTF-8 截断问题
                    self.accumulatedText = fullText
                    print(">>> [QwenASR Stream] delta: \(delta)")
                    self.onPartialResult?(fullText)
                }
            }
        }
    }

    private func transcribeSegment(_ segment: SpeechSegment) {
        guard let recognizer = offlineRecognizer else { return }

        if let text = recognizer.transcribe(samples: segment.samples) {
            let newAccumulated: String = stateQueue.sync {
                if _accumulatedText.isEmpty {
                    _accumulatedText = text
                } else {
                    _accumulatedText += text
                }
                return _accumulatedText
            }

            print(">>> 分段识别结果: \(text)")
            print(">>> 累积文字: \(newAccumulated)")

            DispatchQueue.main.async { [weak self] in
                // 通知 UI 更新
                self?.onPartialResult?(newAccumulated)
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
        print("停止录音")

        // 根据模型类型获取原始文本，然后统一处理标点
        switch currentModel {
        case .funasrNano:
            flushFunASR { [weak self] rawText in
                self?.finalizeAndComplete(rawText: rawText, completion: completion)
            }
        case .streamingParaformer:
            flushStreaming { [weak self] rawText in
                self?.finalizeAndComplete(rawText: rawText, completion: completion)
            }
        case .qwenASR:
            flushQwenStreaming { rawText in
                guard !rawText.isEmpty else {
                    print(">>> [QwenASR] 最终识别结果: （无）")
                    completion(nil)
                    return
                }
                print(">>> [QwenASR] 最终结果: \(rawText)")
                completion(rawText)
            }
        }
    }

    /// 刷新 FunASR 剩余音频并获取原始文本
    private func flushFunASR(completion: @escaping (String) -> Void) {
        vad?.flush()

        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            while self.vad?.hasSegment() == true {
                if let segment = self.vad?.popSegmentWithTime(),
                   let text = self.offlineRecognizer?.transcribe(samples: segment.samples) {
                    self.stateQueue.sync {
                        self._accumulatedText += text
                    }
                }
            }

            let rawText = self.accumulatedText
            DispatchQueue.main.async {
                completion(rawText)
            }
        }
    }

    /// 刷新 Streaming Paraformer 并获取原始文本
    private func flushStreaming(completion: @escaping (String) -> Void) {
        guard let recognizer = onlineRecognizer else {
            completion("")
            return
        }

        // 在识别队列中完成刷新，确保不阻塞主线程
        recognitionQueue.async { [weak self] in
            // 注入 0.3 秒静音触发剩余帧解码
            let silencePadding = [Float](repeating: 0.0, count: 4800)
            recognizer.acceptWaveform(samples: silencePadding)

            while recognizer.isReady() {
                recognizer.decode()
            }

            let text = recognizer.getResult()
            recognizer.reset()

            DispatchQueue.main.async {
                let finalText = text.isEmpty ? (self?.accumulatedText ?? "") : text
                completion(finalText)
            }
        }
    }

    /// 刷新 QwenASR 流式识别器并获取最终文本
    private func flushQwenStreaming(completion: @escaping (String) -> Void) {
        guard let recognizer = qwenStreamRecognizer else {
            completion("")
            return
        }

        // 在 recognitionQueue 中排队执行 finalize，确保之前的 pushAudio 全部完成
        recognitionQueue.async { [weak self] in
            // 注入静音 padding（2 秒 = 1 个 chunk），确保尾部音频被处理
            // 类似 Streaming Paraformer 的 flushStreaming 策略
            let silencePadding = [Float](repeating: 0.0, count: 32000)
            _ = recognizer.pushAudio(samples: silencePadding, finalize: true)

            let result = recognizer.getResult()
            recognizer.reset()

            DispatchQueue.main.async {
                let finalText = result.isEmpty ? (self?.accumulatedText ?? "") : result
                completion(finalText)
            }
        }
    }

    /// 统一的最终处理：添加标点并回调
    private func finalizeAndComplete(rawText: String, completion: @escaping (String?) -> Void) {
        guard !rawText.isEmpty else {
            print(">>> 最终识别结果: （无）")
            completion(nil)
            return
        }

        let finalText = punctuator?.addPunctuation(text: rawText) ?? rawText
        print(">>> 原始文本: \(rawText)")
        print(">>> 标点处理后: \(finalText)")
        completion(finalText)
    }

    var isInitialized: Bool {
        switch currentModel {
        case .funasrNano:
            return offlineRecognizer != nil
        case .streamingParaformer:
            return onlineRecognizer != nil
        case .qwenASR:
            return qwenStreamRecognizer != nil
        }
    }

    /// 重新加载模型（下载完成后调用）
    func reloadModel() {
        offlineRecognizer = nil
        onlineRecognizer = nil
        qwenStreamRecognizer = nil
        vad = nil
        Task { await initializeRecognizer() }
    }

    // MARK: - Test Support

    #if DEBUG
    /// 创建可测试的实例（注入 Mock 识别器）
    static func testable(withQwenRecognizer recognizer: ASRStreamRecognizing?) -> RecordingManager {
        let manager = RecordingManager()
        manager.qwenStreamRecognizer = recognizer
        return manager
    }

    /// 暴露给测试的 QwenASR 流式处理入口
    func testableProcessWithQwenStreaming(samples: [Float]) {
        processWithQwenStreaming(samples: samples)
    }

    /// 暴露给测试的 QwenASR flush 入口
    func testableFlushQwenStreaming(completion: @escaping (String) -> Void) {
        flushQwenStreaming(completion: completion)
    }

    /// 暴露给测试的累积文本
    var testableAccumulatedText: String {
        get { accumulatedText }
        set { accumulatedText = newValue }
    }
    #endif
}
