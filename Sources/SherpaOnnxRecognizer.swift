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
        config.model_config.provider = toCString("coreml")

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
        guard data.count > 12 else {
            print(">>> WAV 文件太小")
            return nil
        }

        // 检查 RIFF 标识
        let riff = String(data: data[0..<4], encoding: .ascii)
        guard riff == "RIFF" else {
            print(">>> 不是有效的 WAV 文件")
            return nil
        }

        // 检查 WAVE 标识
        let wave = String(data: data[8..<12], encoding: .ascii)
        guard wave == "WAVE" else {
            print(">>> 不是有效的 WAVE 文件")
            return nil
        }

        // 遍历 chunks 查找 fmt 和 data
        var sampleRate: Int = 0
        var bitsPerSample: Int = 0
        var numChannels: Int = 0
        var dataOffset: Int = 0
        var dataSize: Int = 0

        var offset = 12 // 跳过 RIFF header
        while offset < data.count - 8 {
            let chunkId = String(data: data[offset..<offset+4], encoding: .ascii)
            let chunkSize = data.withUnsafeBytes { ptr -> Int in
                return Int(ptr.load(fromByteOffset: offset + 4, as: UInt32.self))
            }

            if chunkId == "fmt " {
                // fmt chunk: 包含音频格式信息
                // offset + 8: audioFormat (2 bytes)
                // offset + 10: numChannels (2 bytes)
                // offset + 12: sampleRate (4 bytes)
                // offset + 16: byteRate (4 bytes)
                // offset + 20: blockAlign (2 bytes)
                // offset + 22: bitsPerSample (2 bytes)
                guard offset + 24 <= data.count else {
                    print(">>> fmt chunk 不完整")
                    return nil
                }

                numChannels = data.withUnsafeBytes { ptr -> Int in
                    return Int(ptr.load(fromByteOffset: offset + 10, as: UInt16.self))
                }
                sampleRate = data.withUnsafeBytes { ptr -> Int in
                    return Int(ptr.load(fromByteOffset: offset + 12, as: UInt32.self))
                }
                bitsPerSample = data.withUnsafeBytes { ptr -> Int in
                    return Int(ptr.load(fromByteOffset: offset + 22, as: UInt16.self))
                }

                print(">>> WAV 格式: \(numChannels) 声道, \(sampleRate) Hz, \(bitsPerSample) bit")
            } else if chunkId == "data" {
                dataOffset = offset + 8
                dataSize = chunkSize
                break
            }

            // 移动到下一个 chunk (chunk 大小需要按 2 字节对齐)
            let paddedSize = (chunkSize + 1) & ~1
            offset += 8 + paddedSize
        }

        guard dataOffset > 0, dataSize > 0 else {
            print(">>> 找不到 data chunk")
            return nil
        }

        guard sampleRate > 0, bitsPerSample > 0, numChannels > 0 else {
            print(">>> 找不到 fmt chunk 或格式信息无效")
            return nil
        }

        // 读取音频数据
        let audioData = data[dataOffset..<min(dataOffset + dataSize, data.count)]
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
