import Foundation
import AVFoundation
import WhisperKit

/// 语音识别引擎类型
enum RecognitionEngine {
    case whisper
    case paraformer
    case sensevoice
}

/// 管理音频录制和语音识别
class RecordingManager {
    /// 单例实例
    static let shared = RecordingManager()

    private var audioRecorder: AVAudioRecorder?
    private var whisperKit: WhisperKit?
    private var sherpaRecognizer: SherpaOnnxRecognizer?
    private var recordingURL: URL?
    private var isRecording = false
    private var currentModelId: String = ""
    private var isInitializing = false

    init() {
        Task {
            await initializeRecognizer()
        }
    }

    /// 切换到指定模型并立即加载
    /// - Parameter modelId: 模型 ID
    func switchToModel(_ modelId: String) {
        guard modelId != currentModelId else {
            print(">>> 模型未变更，无需重新加载: \(modelId)")
            return
        }

        print(">>> 切换模型: \(currentModelId) -> \(modelId)")

        // 释放当前模型
        whisperKit = nil
        sherpaRecognizer = nil

        // 立即加载新模型
        Task {
            await initializeRecognizer()
        }
    }

    private func getSelectedModelId() -> String {
        // 从 UserDefaults 读取模型设置，默认为 "paraformer"
        return UserDefaults.standard.string(forKey: "modelSize") ?? "paraformer"
    }

    private func getEngineType(for modelId: String) -> RecognitionEngine {
        switch modelId {
        case "paraformer":
            return .paraformer
        case "sensevoice-small":
            return .sensevoice
        default:
            return .whisper
        }
    }

    private func initializeRecognizer() async {
        // 防止重复初始化
        guard !isInitializing else {
            print(">>> 识别器正在初始化中，跳过重复调用")
            return
        }
        isInitializing = true
        defer { isInitializing = false }

        let modelId = getSelectedModelId()
        currentModelId = modelId
        let engine = getEngineType(for: modelId)

        print("========== 开始加载语音识别模型 ==========")
        print("模型 ID: \(modelId)")
        print("引擎类型: \(engine)")
        print("开始时间: \(Date())")

        switch engine {
        case .whisper:
            await initializeWhisper(modelName: modelId)
        case .paraformer, .sensevoice:
            await initializeSherpaOnnx(modelId: modelId)
        }
    }

    private func initializeWhisper(modelName: String) async {
        // 使用 Application Support 目录，避免触发文稿文件夹访问弹窗
        let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Typeless/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")

        // 检查模型完整性
        let isModelComplete = checkWhisperModelIntegrity(at: modelFolder)
        if !isModelComplete {
            print("⚠️ 检测到 Whisper 模型不完整或不存在，将删除并重新下载...")
            try? FileManager.default.removeItem(at: modelFolder)
            let cacheFolder = modelFolder.deletingLastPathComponent().appendingPathComponent(".cache")
            try? FileManager.default.removeItem(at: cacheFolder)
        } else {
            print("✓ Whisper 模型文件完整性检查通过")
        }

        print("提示: 首次下载模型可能需要几分钟，请耐心等待...")

        // WhisperKit 模型存储的父目录
        let whisperModelRepo = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Typeless/huggingface/models/argmaxinc/whisperkit-coreml")
        try? FileManager.default.createDirectory(at: whisperModelRepo, withIntermediateDirectories: true)

        do {
            print(">>> 正在初始化 WhisperKit...")
            whisperKit = try await WhisperKit(
                model: modelName,
                modelFolder: whisperModelRepo.path,
                verbose: true,
                logLevel: .debug,
                prewarm: false,
                load: true,
                download: true
            )
            print("========== WhisperKit 初始化成功 ==========")
            print("完成时间: \(Date())")

            await warmupWhisperModel()
        } catch {
            print("========== WhisperKit 初始化失败 ==========")
            print("失败时间: \(Date())")
            print("错误类型: \(type(of: error))")
            print("错误信息: \(error)")
            print("错误详情: \(error.localizedDescription)")

            print(">>> 正在清理可能损坏的模型文件...")
            try? FileManager.default.removeItem(at: modelFolder)
            print(">>> 模型已清理，请重启应用以重新下载模型")
        }
    }

    private func initializeSherpaOnnx(modelId: String) async {
        print(">>> Sherpa-ONNX 引擎初始化 (模型: \(modelId))")

        // 检查模型是否已下载
        guard SherpaOnnxManager.shared.isModelDownloaded(modelId) else {
            print("⚠️ \(modelId) 模型未下载，请在设置中下载")
            return
        }

        print("✓ \(modelId) 模型已下载")

        // 获取模型路径
        let modelType: SherpaOnnxRecognizer.ModelType
        let modelPath: String
        let tokensPath: String

        switch modelId {
        case "paraformer":
            modelType = .paraformer
            if let model = SherpaOnnxManager.shared.getParaformerModelPath() {
                modelPath = model.modelPath
                tokensPath = model.tokensPath
            } else {
                print(">>> 无法获取 Paraformer 模型路径")
                return
            }
        case "sensevoice-small":
            modelType = .sensevoice
            if let model = SherpaOnnxManager.shared.getSenseVoiceModelPath() {
                modelPath = model.modelPath
                tokensPath = model.tokensPath
            } else {
                print(">>> 无法获取 SenseVoice 模型路径")
                return
            }
        default:
            print(">>> 不支持的 Sherpa-ONNX 模型: \(modelId)")
            return
        }

        // 创建识别器
        sherpaRecognizer = SherpaOnnxRecognizer(
            modelType: modelType,
            modelPath: modelPath,
            tokensPath: tokensPath
        )

        if sherpaRecognizer != nil {
            print("========== Sherpa-ONNX 初始化成功 ==========")
            print("完成时间: \(Date())")
        } else {
            print("========== Sherpa-ONNX 初始化失败 ==========")
        }
    }

    /// 检查 Whisper 模型文件完整性
    private func checkWhisperModelIntegrity(at modelFolder: URL) -> Bool {
        let fileManager = FileManager.default

        // 检查模型文件夹是否存在
        guard fileManager.fileExists(atPath: modelFolder.path) else {
            print("  - 模型文件夹不存在")
            return false
        }

        // 必需的 mlmodelc 目录及其 weights 子目录
        let requiredModels = [
            "AudioEncoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "TextDecoder.mlmodelc"
        ]

        for model in requiredModels {
            let modelPath = modelFolder.appendingPathComponent(model)
            let weightsPath = modelPath.appendingPathComponent("weights/weight.bin")

            // 检查 mlmodelc 目录存在
            guard fileManager.fileExists(atPath: modelPath.path) else {
                print("  - \(model): ✗ (目录不存在)")
                return false
            }

            // 检查 weights/weight.bin 存在（某些模型可能不需要）
            if !fileManager.fileExists(atPath: weightsPath.path) {
                // 检查是否有 model.mil 文件（有些模型用这个代替 weights）
                let milPath = modelPath.appendingPathComponent("model.mil")
                if fileManager.fileExists(atPath: milPath.path) {
                    // 如果有 model.mil，还需要检查它引用的 weights 是否存在
                    // 读取 model.mil 检查是否引用了 weight.bin
                    if let milContent = try? String(contentsOf: milPath, encoding: .utf8),
                       milContent.contains("weight.bin") {
                        print("  - \(model): ✗ (缺少 weights/weight.bin)")
                        return false
                    }
                }
            }
            print("  - \(model): ✓")
        }

        // 检查 config.json
        let configPath = modelFolder.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: configPath.path) else {
            print("  - config.json: ✗")
            return false
        }
        print("  - config.json: ✓")

        return true
    }

    private func warmupWhisperModel() async {
        guard let whisper = whisperKit else { return }

        print("正在预热模型...")
        do {
            // 创建一小段静音音频数据进行预热
            let sampleRate = 16000
            let duration = 0.5 // 0.5秒静音
            let sampleCount = Int(Double(sampleRate) * duration)
            let silentAudio = [Float](repeating: 0.0, count: sampleCount)

            // 执行一次转录来预热模型
            let options = DecodingOptions(
                task: .transcribe,
                language: "zh"
            )
            _ = try await whisper.transcribe(audioArray: silentAudio, decodeOptions: options)
            print("模型预热完成")
        } catch {
            print("模型预热失败（可忽略）: \(error)")
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        // 检查是否需要重新加载模型
        reloadModelIfNeeded()

        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("typeless_recording_\(UUID().uuidString).wav")

        guard let url = recordingURL else { return }

        // 配置录音设置 - Whisper 需要 16kHz 采样率
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            print("开始录音: \(url.path)")
        } catch {
            print("录音启动失败: \(error)")
        }
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
        guard isRecording, let recorder = audioRecorder else {
            completion(nil)
            return
        }

        recorder.stop()
        isRecording = false
        print("停止录音")

        guard let url = recordingURL else {
            completion(nil)
            return
        }

        // 异步进行语音识别
        Task {
            let text = await transcribe(audioURL: url)

            // 清理临时文件
            try? FileManager.default.removeItem(at: url)

            await MainActor.run {
                completion(text)
            }
        }
    }

    private func transcribe(audioURL: URL) async -> String? {
        // 如果模型正在初始化，等待完成
        while isInitializing {
            print(">>> 等待模型初始化完成...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        let engine = getEngineType(for: currentModelId)

        switch engine {
        case .whisper:
            return await transcribeWithWhisper(audioURL: audioURL)
        case .paraformer, .sensevoice:
            return await transcribeWithSherpaOnnx(audioURL: audioURL)
        }
    }

    private func transcribeWithWhisper(audioURL: URL) async -> String? {
        guard let whisper = whisperKit else {
            print("WhisperKit 未初始化，当前选择的模型可能未下载")
            return nil
        }

        do {
            // 配置解码选项，支持中英文混合识别
            let options = DecodingOptions(
                task: .transcribe,
                language: "zh",
                temperatureFallbackCount: 3,
                usePrefillPrompt: true
            )

            let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)

            // 合并所有转录结果
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            print("转录结果: \(text)")
            return text.isEmpty ? nil : text
        } catch {
            print("转录失败: \(error)")
            return nil
        }
    }

    private func transcribeWithSherpaOnnx(audioURL: URL) async -> String? {
        guard let recognizer = sherpaRecognizer else {
            print(">>> Sherpa-ONNX 识别器未初始化")
            return nil
        }

        print(">>> 开始 Sherpa-ONNX 转录...")
        let text = recognizer.transcribe(audioURL: audioURL)
        if let text = text {
            print("转录结果: \(text)")
        }
        return text
    }

    var isInitialized: Bool {
        let engine = getEngineType(for: currentModelId)
        switch engine {
        case .whisper:
            return whisperKit != nil
        case .paraformer, .sensevoice:
            return sherpaRecognizer != nil
        }
    }

    /// 检查是否需要重新加载模型（如果用户切换了模型设置）
    func reloadModelIfNeeded() {
        let selectedModel = getSelectedModelId()
        if selectedModel != currentModelId && !isInitializing {
            print("检测到模型设置变更: \(currentModelId) -> \(selectedModel)")
            whisperKit = nil
            sherpaRecognizer = nil
            Task {
                await initializeRecognizer()
            }
        }
    }
}
