import Foundation
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

/// Sherpa-ONNX 离线语音识别器
class SherpaOnnxRecognizer {
    private var recognizer: OpaquePointer?

    /// 初始化识别器
    init?(modelPath: String, tokensPath: String) {
        print(">>> SherpaOnnxRecognizer: 开始初始化...")
        print("    模型路径: \(modelPath)")
        print("    Tokens路径: \(tokensPath)")

        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            print(">>> SherpaOnnxRecognizer: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOfflineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80

        // 模型配置
        config.model_config.tokens = toCString(tokensPath)
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.model_config.provider = toCString("cpu")
        config.model_config.sense_voice.model = toCString(modelPath)
        config.model_config.sense_voice.language = toCString("auto")
        config.model_config.sense_voice.use_itn = 1
        config.model_config.model_type = toCString("sense_voice")

        // 解码配置
        config.decoding_method = toCString("greedy_search")
        config.max_active_paths = 4

        recognizer = SherpaOnnxCreateOfflineRecognizer(&config)

        if recognizer == nil {
            print(">>> SherpaOnnxRecognizer: 创建识别器失败")
            return nil
        }

        print(">>> SherpaOnnxRecognizer: 初始化成功")
    }

    deinit {
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
    }

    /// 转录音频数据
    func transcribe(samples: [Float], sampleRate: Int32 = 16000) -> String? {
        guard let recognizer = recognizer else { return nil }
        guard !samples.isEmpty else { return nil }

        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            return nil
        }

        defer { SherpaOnnxDestroyOfflineStream(stream) }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, sampleRate, buffer.baseAddress, Int32(samples.count))
        }

        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            return nil
        }

        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

        guard let textPtr = result.pointee.text else { return nil }

        // 过滤 FunASR 特殊标记（如 <|nospeech|>, <|HAPPY|>, <|en|> 等）
        var text = String(cString: textPtr)
        text = text.replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 从 WAV 文件转录
    func transcribe(audioURL: URL) -> String? {
        guard let audioData = readWavFile(url: audioURL) else {
            print(">>> SherpaOnnxRecognizer: 读取音频文件失败")
            return nil
        }
        return transcribe(samples: audioData.samples, sampleRate: Int32(audioData.sampleRate))
    }

    // MARK: - Private

    private func toCString(_ string: String) -> UnsafePointer<CChar>? {
        return UnsafePointer(strdup(string))
    }

    private func readWavFile(url: URL) -> (samples: [Float], sampleRate: Int)? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else {
            return nil
        }

        // 检查 RIFF/WAVE 标识
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return nil
        }

        // 解析 fmt chunk
        var sampleRate = 0
        var bitsPerSample = 0
        var numChannels = 0
        var dataOffset = 0
        var dataSize = 0

        var offset = 12
        while offset < data.count - 8 {
            let chunkId = String(data: data[offset..<offset+4], encoding: .ascii)
            let chunkSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self) }

            if chunkId == "fmt " && offset + 24 <= data.count {
                numChannels = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 10, as: UInt16.self) })
                sampleRate = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 12, as: UInt32.self) })
                bitsPerSample = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 22, as: UInt16.self) })
            } else if chunkId == "data" {
                dataOffset = offset + 8
                dataSize = Int(chunkSize)
                break
            }

            offset += 8 + Int((chunkSize + 1) & ~1)
        }

        guard dataOffset > 0, dataSize > 0, sampleRate > 0, bitsPerSample == 16, numChannels > 0 else {
            return nil
        }

        // 读取音频数据
        let audioData = data[dataOffset..<min(dataOffset + dataSize, data.count)]
        var samples: [Float] = []
        let sampleCount = audioData.count / (2 * numChannels)
        samples.reserveCapacity(sampleCount)

        audioData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples.append(Float(int16Ptr[i * numChannels]) / 32768.0)
            }
        }

        return (samples, sampleRate)
    }
}
