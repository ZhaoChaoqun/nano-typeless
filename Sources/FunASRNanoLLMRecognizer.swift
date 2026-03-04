import Foundation
import os
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "FunASRNanoLLM")

/// FunASR Nano LLM 离线语音识别器
/// 使用 SenseVoice encoder + Qwen3-0.6B LLM 进行高质量语音转文字
class FunASRNanoLLMRecognizer {
    private var recognizer: OpaquePointer?
    private let cStrings = CStringLifetime()

    init?(encoderAdaptorPath: String, llmPath: String, embeddingPath: String, tokenizerDir: String) {
        logger.info("FunASRNanoLLMRecognizer: 开始初始化...")

        guard FileManager.default.fileExists(atPath: encoderAdaptorPath),
              FileManager.default.fileExists(atPath: llmPath),
              FileManager.default.fileExists(atPath: embeddingPath) else {
            logger.info("FunASRNanoLLMRecognizer: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOfflineRecognizerConfig()

        // 特征配置
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80

        // FunASR Nano 模型配置
        config.model_config.funasr_nano.encoder_adaptor = cStrings.makeCString(encoderAdaptorPath)
        config.model_config.funasr_nano.llm = cStrings.makeCString(llmPath)
        config.model_config.funasr_nano.embedding = cStrings.makeCString(embeddingPath)
        config.model_config.funasr_nano.tokenizer = cStrings.makeCString(tokenizerDir)
        config.model_config.funasr_nano.system_prompt = cStrings.makeCString("You are a helpful assistant.")
        config.model_config.funasr_nano.user_prompt = cStrings.makeCString("语音转写：")
        config.model_config.funasr_nano.language = cStrings.makeCString("")
        config.model_config.funasr_nano.itn = 1
        config.model_config.funasr_nano.hotwords = cStrings.makeCString("")
        config.model_config.funasr_nano.max_new_tokens = 512
        config.model_config.funasr_nano.temperature = 1e-6
        config.model_config.funasr_nano.top_p = 0.8
        config.model_config.funasr_nano.seed = 42

        let threads = ProcessInfo.processInfo.activeProcessorCount
        config.model_config.num_threads = Int32(threads)
        logger.info("FunASRNanoLLMRecognizer: num_threads=\(threads)")
        config.model_config.debug = 0
        config.model_config.provider = cStrings.makeCString("cpu")
        config.model_config.model_type = cStrings.makeCString("")

        // 解码配置
        config.decoding_method = cStrings.makeCString("greedy_search")
        config.max_active_paths = 4

        recognizer = SherpaOnnxCreateOfflineRecognizer(&config)

        if recognizer == nil {
            logger.info("FunASRNanoLLMRecognizer: 创建识别器失败")
            return nil
        }

        logger.info("FunASRNanoLLMRecognizer: 初始化成功")
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

        var text = String(cString: textPtr)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
