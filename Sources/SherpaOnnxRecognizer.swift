import Foundation
import os
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxRecognizer")

/// Sherpa-ONNX 离线语音识别器
class SherpaOnnxRecognizer {
    private var recognizer: OpaquePointer?
    private let cStrings = CStringLifetime()

    /// 初始化识别器
    init?(modelPath: String, tokensPath: String) {
        logger.info("SherpaOnnxRecognizer: 开始初始化...")
        logger.debug("模型路径: \(modelPath)")
        logger.debug("Tokens路径: \(tokensPath)")

        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            logger.info("SherpaOnnxRecognizer: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOfflineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80

        // 模型配置
        config.model_config.tokens = cStrings.makeCString(tokensPath)
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.model_config.provider = cStrings.makeCString("cpu")
        config.model_config.sense_voice.model = cStrings.makeCString(modelPath)
        config.model_config.sense_voice.language = cStrings.makeCString("auto")
        config.model_config.sense_voice.use_itn = 1
        config.model_config.model_type = cStrings.makeCString("sense_voice")

        // 解码配置
        config.decoding_method = cStrings.makeCString("greedy_search")
        config.max_active_paths = 4

        recognizer = SherpaOnnxCreateOfflineRecognizer(&config)

        if recognizer == nil {
            logger.info("SherpaOnnxRecognizer: 创建识别器失败")
            return nil
        }

        logger.info("SherpaOnnxRecognizer: 初始化成功")
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

        // 移除中文和英文之间的空格
        text = text.replacingOccurrences(of: "([\\u4e00-\\u9fa5])\\s+([a-zA-Z0-9])", with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "([a-zA-Z0-9])\\s+([\\u4e00-\\u9fa5])", with: "$1$2", options: .regularExpression)

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
