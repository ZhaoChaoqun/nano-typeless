import Foundation
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

/// Sherpa-ONNX 离线语音识别器
/// 支持 Paraformer 和 SenseVoice 模型
class SherpaOnnxRecognizer {
    private var recognizer: OpaquePointer?
    private let modelType: ModelType

    enum ModelType {
        case paraformer
        case sensevoice
    }

    /// 初始化识别器
    /// - Parameters:
    ///   - modelType: 模型类型
    ///   - modelPath: 模型文件路径
    ///   - tokensPath: tokens 文件路径
    init?(modelType: ModelType, modelPath: String, tokensPath: String) {
        self.modelType = modelType

        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            print(">>> SherpaOnnxRecognizer: 模型文件不存在")
            print("    模型路径: \(modelPath)")
            print("    Tokens路径: \(tokensPath)")
            return nil
        }

        var config = createConfig(modelType: modelType, modelPath: modelPath, tokensPath: tokensPath)

        recognizer = SherpaOnnxCreateOfflineRecognizer(&config)

        if recognizer == nil {
            print(">>> SherpaOnnxRecognizer: 创建识别器失败")
            return nil
        }

        print(">>> SherpaOnnxRecognizer: 初始化成功 (类型: \(modelType))")
    }

    deinit {
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
    }

    /// 转录音频数据
    /// - Parameters:
    ///   - samples: 音频采样数据（归一化到 [-1, 1]）
    ///   - sampleRate: 采样率
    /// - Returns: 识别文本
    func transcribe(samples: [Float], sampleRate: Int32 = 16000) -> String? {
        guard let recognizer = recognizer else {
            print(">>> SherpaOnnxRecognizer: 识别器未初始化")
            return nil
        }

        guard !samples.isEmpty else {
            print(">>> SherpaOnnxRecognizer: 音频数据为空")
            return nil
        }

        // 创建流
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            print(">>> SherpaOnnxRecognizer: 创建流失败")
            return nil
        }

        defer {
            SherpaOnnxDestroyOfflineStream(stream)
        }

        // 输入音频数据
        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, sampleRate, buffer.baseAddress, Int32(samples.count))
        }

        // 解码
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        // 获取结果
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            print(">>> SherpaOnnxRecognizer: 获取结果失败")
            return nil
        }

        defer {
            SherpaOnnxDestroyOfflineRecognizerResult(result)
        }

        guard let textPtr = result.pointee.text else {
            return nil
        }

        let text = String(cString: textPtr).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 从 WAV 文件转录
    /// - Parameter url: WAV 文件 URL
    /// - Returns: 识别文本
    func transcribe(audioURL: URL) -> String? {
        guard let audioData = readWavFile(url: audioURL) else {
            print(">>> SherpaOnnxRecognizer: 读取音频文件失败")
            return nil
        }

        return transcribe(samples: audioData.samples, sampleRate: Int32(audioData.sampleRate))
    }

    // MARK: - Private

    /// 将字符串转换为 C 字符串指针（需要手动管理内存）
    private func toCString(_ string: String) -> UnsafePointer<CChar>? {
        return UnsafePointer(strdup(string))
    }

    private func createConfig(modelType: ModelType, modelPath: String, tokensPath: String) -> SherpaOnnxOfflineRecognizerConfig {
        var config = SherpaOnnxOfflineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80

        // 模型配置
        config.model_config.tokens = toCString(tokensPath)
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.model_config.provider = toCString("cpu")

        switch modelType {
        case .paraformer:
            config.model_config.paraformer.model = toCString(modelPath)
            config.model_config.model_type = toCString("paraformer")

        case .sensevoice:
            config.model_config.sense_voice.model = toCString(modelPath)
            config.model_config.sense_voice.language = toCString("auto")
            config.model_config.sense_voice.use_itn = 1
            config.model_config.model_type = toCString("sense_voice")
        }

        // 解码配置
        config.decoding_method = toCString("greedy_search")
        config.max_active_paths = 4

        return config
    }

    /// 读取 WAV 文件
    private func readWavFile(url: URL) -> (samples: [Float], sampleRate: Int)? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        // 解析 WAV 头
        guard data.count > 44 else {
            print(">>> WAV 文件太小")
            return nil
        }

        // 检查 RIFF 标识
        let riff = String(data: data[0..<4], encoding: .ascii)
        guard riff == "RIFF" else {
            print(">>> 不是有效的 WAV 文件")
            return nil
        }

        // 获取采样率 (偏移 24-27)
        let sampleRate = data.withUnsafeBytes { ptr -> Int in
            return Int(ptr.load(fromByteOffset: 24, as: UInt32.self))
        }

        // 获取位深度 (偏移 34-35)
        let bitsPerSample = data.withUnsafeBytes { ptr -> Int in
            return Int(ptr.load(fromByteOffset: 34, as: UInt16.self))
        }

        // 获取声道数 (偏移 22-23)
        let numChannels = data.withUnsafeBytes { ptr -> Int in
            return Int(ptr.load(fromByteOffset: 22, as: UInt16.self))
        }

        // 查找 data chunk
        var dataOffset = 12
        while dataOffset < data.count - 8 {
            let chunkId = String(data: data[dataOffset..<dataOffset+4], encoding: .ascii)
            let chunkSize = data.withUnsafeBytes { ptr -> Int in
                return Int(ptr.load(fromByteOffset: dataOffset + 4, as: UInt32.self))
            }

            if chunkId == "data" {
                dataOffset += 8
                break
            }
            dataOffset += 8 + chunkSize
        }

        guard dataOffset < data.count else {
            print(">>> 找不到 data chunk")
            return nil
        }

        // 读取音频数据
        let audioData = data[dataOffset...]
        var samples: [Float] = []

        if bitsPerSample == 16 {
            let sampleCount = audioData.count / (2 * numChannels)
            samples.reserveCapacity(sampleCount)

            audioData.withUnsafeBytes { ptr in
                let int16Ptr = ptr.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    // 如果是多声道，只取第一个声道
                    let value = Float(int16Ptr[i * numChannels]) / 32768.0
                    samples.append(value)
                }
            }
        } else if bitsPerSample == 32 {
            let sampleCount = audioData.count / (4 * numChannels)
            samples.reserveCapacity(sampleCount)

            audioData.withUnsafeBytes { ptr in
                let floatPtr = ptr.bindMemory(to: Float.self)
                for i in 0..<sampleCount {
                    samples.append(floatPtr[i * numChannels])
                }
            }
        } else {
            print(">>> 不支持的位深度: \(bitsPerSample)")
            return nil
        }

        return (samples, sampleRate)
    }
}
