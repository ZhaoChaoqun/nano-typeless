import Foundation
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

/// Sherpa-ONNX 流式语音识别器（Streaming Paraformer）
class SherpaOnnxOnlineRecognizer {
    private var recognizer: OpaquePointer?
    private var stream: OpaquePointer?
    private let cStrings = CStringLifetime()

    /// 初始化流式识别器
    init?(encoderPath: String, decoderPath: String, tokensPath: String) {
        print(">>> SherpaOnnxOnlineRecognizer: 开始初始化...")
        print("    Encoder路径: \(encoderPath)")
        print("    Decoder路径: \(decoderPath)")
        print("    Tokens路径: \(tokensPath)")

        guard FileManager.default.fileExists(atPath: encoderPath),
              FileManager.default.fileExists(atPath: decoderPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            print(">>> SherpaOnnxOnlineRecognizer: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOnlineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80

        // Paraformer 模型配置
        config.model_config.paraformer.encoder = cStrings.makeCString(encoderPath)
        config.model_config.paraformer.decoder = cStrings.makeCString(decoderPath)
        config.model_config.tokens = cStrings.makeCString(tokensPath)
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.model_config.provider = cStrings.makeCString("cpu")
        config.model_config.model_type = cStrings.makeCString("paraformer")

        // 解码配置
        config.decoding_method = cStrings.makeCString("greedy_search")
        config.max_active_paths = 4

        // 端点检测配置
        config.enable_endpoint = 1
        config.rule1_min_trailing_silence = 2.4  // 无语音时的静音阈值（秒）
        config.rule2_min_trailing_silence = 1.2  // 有语音后的静音阈值（秒）
        config.rule3_min_utterance_length = 20   // 最大语句长度（秒）

        recognizer = SherpaOnnxCreateOnlineRecognizer(&config)

        if recognizer == nil {
            print(">>> SherpaOnnxOnlineRecognizer: 创建识别器失败")
            return nil
        }

        // 创建初始流
        stream = SherpaOnnxCreateOnlineStream(recognizer)
        if stream == nil {
            print(">>> SherpaOnnxOnlineRecognizer: 创建流失败")
            SherpaOnnxDestroyOnlineRecognizer(recognizer)
            recognizer = nil
            return nil
        }

        print(">>> SherpaOnnxOnlineRecognizer: 初始化成功")
    }

    deinit {
        if let stream = stream {
            SherpaOnnxDestroyOnlineStream(stream)
        }
        if let recognizer = recognizer {
            SherpaOnnxDestroyOnlineRecognizer(recognizer)
        }
    }

    /// 接收音频数据
    func acceptWaveform(samples: [Float], sampleRate: Int32 = 16000) {
        guard let stream = stream else { return }
        guard !samples.isEmpty else { return }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxOnlineStreamAcceptWaveform(stream, sampleRate, buffer.baseAddress, Int32(samples.count))
        }
    }

    /// 检查是否有足够的帧进行解码
    func isReady() -> Bool {
        guard let recognizer = recognizer, let stream = stream else { return false }
        return SherpaOnnxIsOnlineStreamReady(recognizer, stream) == 1
    }

    /// 执行解码
    func decode() {
        guard let recognizer = recognizer, let stream = stream else { return }
        SherpaOnnxDecodeOnlineStream(recognizer, stream)
    }

    /// 获取当前识别结果
    func getResult() -> String {
        guard let recognizer = recognizer, let stream = stream else { return "" }

        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else {
            return ""
        }

        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }

        guard let textPtr = result.pointee.text else { return "" }

        var text = String(cString: textPtr)

        // 移除中文和英文之间的空格
        text = text.replacingOccurrences(of: "([\\u4e00-\\u9fa5])\\s+([a-zA-Z0-9])", with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "([a-zA-Z0-9])\\s+([\\u4e00-\\u9fa5])", with: "$1$2", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 检查是否检测到端点（句子结束）
    func isEndpoint() -> Bool {
        guard let recognizer = recognizer, let stream = stream else { return false }
        return SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) == 1
    }

    /// 重置流状态（用于新的识别会话）
    func reset() {
        guard let recognizer = recognizer, let stream = stream else { return }
        SherpaOnnxOnlineStreamReset(recognizer, stream)
    }

    /// 重新创建流（在 inputFinished 后必须调用此方法才能开始新的识别）
    func recreateStream() {
        // 销毁旧的 stream
        if let oldStream = stream {
            SherpaOnnxDestroyOnlineStream(oldStream)
        }
        // 创建新的 stream
        stream = SherpaOnnxCreateOnlineStream(recognizer)
        if stream == nil {
            print(">>> SherpaOnnxOnlineRecognizer: 重新创建流失败")
        }
    }

    /// 通知输入结束
    func inputFinished() {
        guard let stream = stream else { return }
        SherpaOnnxOnlineStreamInputFinished(stream)
    }
}
