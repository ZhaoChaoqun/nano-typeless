import Foundation
import AVFoundation
import WhisperKit

/// 管理音频录制和语音识别
class RecordingManager {
    private var audioRecorder: AVAudioRecorder?
    private var whisperKit: WhisperKit?
    private var recordingURL: URL?
    private var isRecording = false

    init() {
        Task {
            await initializeWhisper()
        }
    }

    private func initializeWhisper() async {
        let modelName = "large-v3_turbo"
        let modelFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")

        print("========== 开始加载 WhisperKit 模型 ==========")
        print("模型名称: \(modelName)")
        print("开始时间: \(Date())")

        // 检查模型完整性
        let isModelComplete = checkModelIntegrity(at: modelFolder)
        if !isModelComplete {
            print("⚠️ 检测到模型不完整或不存在，将删除并重新下载...")
            try? FileManager.default.removeItem(at: modelFolder)
            // 同时清理缓存
            let cacheFolder = modelFolder.deletingLastPathComponent().appendingPathComponent(".cache")
            try? FileManager.default.removeItem(at: cacheFolder)
        } else {
            print("✓ 模型文件完整性检查通过")
        }

        print("提示: 首次下载模型可能需要几分钟，请耐心等待...")

        do {
            print(">>> 正在初始化 WhisperKit...")
            whisperKit = try await WhisperKit(
                model: modelName,
                verbose: true,
                logLevel: .debug,
                prewarm: false,
                load: true,
                download: true
            )
            print("========== WhisperKit 初始化成功 ==========")
            print("完成时间: \(Date())")

            // 预热模型
            await warmupModel()
        } catch {
            print("========== WhisperKit 初始化失败 ==========")
            print("失败时间: \(Date())")
            print("错误类型: \(type(of: error))")
            print("错误信息: \(error)")
            print("错误详情: \(error.localizedDescription)")

            // 如果加载失败，尝试删除模型并提示用户重启
            print(">>> 正在清理可能损坏的模型文件...")
            try? FileManager.default.removeItem(at: modelFolder)
            print(">>> 模型已清理，请重启应用以重新下载模型")
        }
    }

    /// 检查模型文件完整性
    private func checkModelIntegrity(at modelFolder: URL) -> Bool {
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

    private func warmupModel() async {
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
        guard let whisper = whisperKit else {
            print("WhisperKit 未初始化")
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

    var isInitialized: Bool {
        whisperKit != nil
    }
}
