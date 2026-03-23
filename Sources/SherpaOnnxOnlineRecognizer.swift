import Foundation
import os
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxOnlineRecognizer")

/// Sherpa-ONNX 流式语音识别器（Streaming Paraformer）
class SherpaOnnxOnlineRecognizer {

    // MARK: - Constants

    /// 音频采样率（Hz）
    private static let sampleRate: Int32 = 16000

    /// 特征维度（Fbank 特征）
    private static let featureDim: Int32 = 80

    /// 推理线程数
    private static let numThreads: Int32 = 1

    /// greedy_search 最大活跃路径数
    private static let maxActivePaths: Int32 = 4

    /// 无语音时的静音阈值（秒）——端点检测规则 1
    private static let rule1MinTrailingSilence: Float = 2.4

    /// 有语音后的静音阈值（秒）——端点检测规则 2
    private static let rule2MinTrailingSilence: Float = 1.2

    /// 最大语句长度（秒）——端点检测规则 3
    private static let rule3MinUtteranceLength: Float = 20

    // MARK: - Properties

    private var recognizer: OpaquePointer?
    private var stream: OpaquePointer?
    private let cStrings = CStringLifetime()

    /// 初始化流式识别器
    init?(encoderPath: String, decoderPath: String, tokensPath: String, ruleFstsPath: String? = nil) {
        logger.info("SherpaOnnxOnlineRecognizer: 开始初始化...")
        logger.debug("Encoder路径: \(encoderPath, privacy: .public)")
        logger.debug("Decoder路径: \(decoderPath, privacy: .public)")
        logger.debug("Tokens路径: \(tokensPath, privacy: .public)")
        if let ruleFstsPath = ruleFstsPath {
            logger.debug("ITN FST路径: \(ruleFstsPath, privacy: .public)")
        }

        guard FileManager.default.fileExists(atPath: encoderPath),
              FileManager.default.fileExists(atPath: decoderPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            logger.info("SherpaOnnxOnlineRecognizer: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOnlineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = Self.sampleRate
        config.feat_config.feature_dim = Self.featureDim

        // Paraformer 模型配置
        config.model_config.paraformer.encoder = cStrings.makeCString(encoderPath)
        config.model_config.paraformer.decoder = cStrings.makeCString(decoderPath)
        config.model_config.tokens = cStrings.makeCString(tokensPath)
        config.model_config.num_threads = Self.numThreads
        config.model_config.debug = 0
        config.model_config.provider = cStrings.makeCString("cpu")
        config.model_config.model_type = cStrings.makeCString("paraformer")

        // 解码配置
        config.decoding_method = cStrings.makeCString("greedy_search")
        config.max_active_paths = Self.maxActivePaths

        // 端点检测配置
        config.enable_endpoint = 1
        config.rule1_min_trailing_silence = Self.rule1MinTrailingSilence
        config.rule2_min_trailing_silence = Self.rule2MinTrailingSilence
        config.rule3_min_utterance_length = Self.rule3MinUtteranceLength

        // ITN 规则（WeTextProcessing WFST: tagger + verbalizer）
        if let ruleFstsPath = ruleFstsPath, !ruleFstsPath.isEmpty {
            config.rule_fsts = cStrings.makeCString(ruleFstsPath)
            logger.info("SherpaOnnxOnlineRecognizer: 已启用 ITN (rule_fsts)")
        }

        recognizer = SherpaOnnxCreateOnlineRecognizer(&config)

        if recognizer == nil {
            logger.info("SherpaOnnxOnlineRecognizer: 创建识别器失败")
            return nil
        }

        // 创建初始流
        stream = SherpaOnnxCreateOnlineStream(recognizer)
        if stream == nil {
            logger.info("SherpaOnnxOnlineRecognizer: 创建流失败")
            SherpaOnnxDestroyOnlineRecognizer(recognizer)
            recognizer = nil
            return nil
        }

        logger.info("SherpaOnnxOnlineRecognizer: 初始化成功")
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

    /// 标记当前 chunk 为最终 chunk（流式 Paraformer 专用）
    /// 启用短 chunk 接受 + CIF 尾部 token flush
    /// 必须在最后一次 acceptWaveform 之后、decode 之前调用
    func setFinalChunk() {
        guard let stream = stream else { return }
        SherpaOnnxOnlineStreamSetFinalChunk(stream)
    }

    /// 标记输入结束，通知解码器不会再有新的音频数据
    func inputFinished() {
        guard let stream = stream else { return }
        SherpaOnnxOnlineStreamInputFinished(stream)
    }

    /// 重置流状态（用于新的识别会话）
    /// 销毁旧 stream 并创建新 stream，彻底清除音频特征缓冲区和解码器状态
    func reset() {
        guard let recognizer = recognizer else { return }
        if let stream = stream {
            SherpaOnnxDestroyOnlineStream(stream)
        }
        stream = SherpaOnnxCreateOnlineStream(recognizer)
    }
}
