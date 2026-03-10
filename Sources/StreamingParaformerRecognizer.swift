import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "StreamingParaformerRecognizer")

/// 流式语音识别器（Streaming Paraformer）
///
/// 使用原生 ONNX Runtime 替代 sherpa-onnx，修复尾部截断问题。
/// 外部接口保持不变。
class StreamingParaformerRecognizer {
    private var engine: ParaformerONNX?

    /// 初始化流式识别器
    init?(encoderPath: String, decoderPath: String, tokensPath: String, ruleFstsPath: String? = nil) {
        logger.info("StreamingParaformerRecognizer: 开始初始化（原生 ORT）...")
        logger.debug("Encoder路径: \(encoderPath, privacy: .public)")
        logger.debug("Decoder路径: \(decoderPath, privacy: .public)")
        logger.debug("Tokens路径: \(tokensPath, privacy: .public)")

        engine = ParaformerONNX(
            encoderPath: encoderPath,
            decoderPath: decoderPath,
            tokensPath: tokensPath
        )

        guard engine != nil else {
            logger.error("StreamingParaformerRecognizer: ParaformerONNX 初始化失败")
            return nil
        }

        logger.info("StreamingParaformerRecognizer: 初始化成功（原生 ORT）")
    }

    /// 接收音频数据
    func acceptWaveform(samples: [Float], sampleRate: Int32 = 16000) {
        engine?.acceptWaveform(samples: samples, sampleRate: sampleRate)
    }

    /// 检查是否有足够的帧进行解码
    func isReady() -> Bool {
        return engine?.isReady() ?? false
    }

    /// 执行解码
    func decode() {
        engine?.decode()
    }

    /// 获取当前识别结果
    func getResult() -> String {
        return engine?.getResult() ?? ""
    }

    /// 标记输入结束，触发 final chunk 处理
    func inputFinished() {
        engine?.inputFinished()
    }

    /// 重置流状态（用于新的识别会话）
    func reset() {
        engine?.reset()
    }

    /// 离线一次性转录（调试/benchmark 用）
    func transcribeOffline(samples: [Float]) -> String {
        return engine?.transcribeOffline(samples: samples) ?? ""
    }
}
