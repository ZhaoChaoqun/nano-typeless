import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "QwenASR")

/// QwenASR 流式识别器
/// 每次推送新音频 chunk，增量返回识别结果
class QwenASRStreamRecognizer {

    // MARK: - Constants

    /// 流式推理的 chunk 长度（秒）
    private static let streamChunkSeconds: Float = 2.0

    /// rollback token 数量：每次推理后回退的 token 数，用于保证上下文一致性
    private static let streamRollbackTokens: Int32 = 5

    /// unfixed chunks 数量：保持未确认的 chunk 数
    private static let streamUnfixedChunks: Int32 = 0

    /// 每个 chunk 最大生成 token 数
    private static let streamMaxNewTokens: Int32 = 32

    /// 离线转写默认分段长度（秒）
    private static let defaultOfflineSegmentSeconds: Float = 20.0

    // MARK: - Properties

    private var engine: OpaquePointer?       // QwenAsrEngine*
    private var streamState: OpaquePointer?  // QwenAsrStreamState*

    init?(modelDir: String, numThreads: Int32 = 0) {
        logger.info("QwenASRStreamRecognizer: 开始初始化...")
        logger.debug("模型目录: \(modelDir, privacy: .public)")

        guard FileManager.default.fileExists(atPath: modelDir) else {
            logger.info("QwenASRStreamRecognizer: 模型目录不存在")
            return nil
        }

        engine = qwen_asr_load_model(modelDir, numThreads, 0)
        guard engine != nil else {
            logger.info("QwenASRStreamRecognizer: 创建引擎失败")
            return nil
        }

        // 强制简体中文输出，避免自动检测导致输出繁体字
        qwen_asr_set_language(engine, "chinese")

        // 启用 Metal GPU 加速
        qwen_asr_set_use_gpu(engine, 1)
        logger.info("QwenASRStreamRecognizer: 已启用 Metal GPU 加速")

        // 流式参数：使用 C API 默认值
        qwen_asr_stream_set_chunk_sec(engine, Self.streamChunkSeconds)
        qwen_asr_stream_set_rollback(engine, Self.streamRollbackTokens)
        qwen_asr_stream_set_unfixed_chunks(engine, Self.streamUnfixedChunks)
        qwen_asr_stream_set_max_new_tokens(engine, Self.streamMaxNewTokens)

        streamState = qwen_asr_stream_new()
        guard streamState != nil else {
            logger.info("QwenASRStreamRecognizer: 创建流式状态失败")
            qwen_asr_free(engine)
            engine = nil
            return nil
        }

        logger.info("QwenASRStreamRecognizer: 初始化成功")

        let isInt8 = qwen_asr_is_int8(engine)
        if isInt8 == 1 {
            logger.info("QwenASRStreamRecognizer: 使用 INT8 量化模型")
        } else {
            logger.info("QwenASRStreamRecognizer: 使用 BF16 原始模型")
        }
    }

    deinit {
        if let s = streamState { qwen_asr_stream_free(s) }
        if let e = engine { qwen_asr_free(e) }
    }

    /// 推送新音频并获取增量文本
    /// - Parameters:
    ///   - samples: 新的 PCM 样本（16kHz mono f32）
    ///   - finalize: 是否结束本次识别（刷新缓冲）
    /// - Returns: 新增文本（delta），无则返回 nil
    func pushAudio(samples: [Float], finalize: Bool = false) -> String? {
        guard let engine = engine, let state = streamState else { return nil }

        let resultPtr = samples.withUnsafeBufferPointer { buffer in
            qwen_asr_stream_push(
                engine, state,
                buffer.baseAddress, Int32(samples.count),
                finalize ? 1 : 0
            )
        }

        guard let resultPtr = resultPtr else { return nil }
        defer { qwen_asr_free_string(resultPtr) }

        let text = String(cString: resultPtr)
        return text.isEmpty ? nil : text
    }

    /// 获取当前累积的完整识别结果
    func getResult() -> String {
        guard let state = streamState else { return "" }
        guard let resultPtr = qwen_asr_stream_get_result(state) else { return "" }
        defer { qwen_asr_free_string(resultPtr) }
        return String(cString: resultPtr)
    }

    /// 获取当前已解码但尚未稳定的投机文本
    func getUnfixed() -> String? {
        guard let state = streamState else { return nil }
        guard let resultPtr = qwen_asr_stream_get_unfixed(state) else { return nil }
        defer { qwen_asr_free_string(resultPtr) }
        let text = String(cString: resultPtr)
        return text.isEmpty ? nil : text
    }

    /// 重置流式状态，开始新一轮识别
    func reset() {
        guard let state = streamState else { return }
        qwen_asr_stream_reset(state)
    }

    /// 离线转写完整音频（适合长语音，使用分段解码）
    /// - Parameters:
    ///   - samples: PCM 样本（16kHz mono f32）
    ///   - segmentSec: 分段长度（秒），默认 20s
    /// - Returns: 完整转写文本
    func transcribeOffline(samples: [Float], segmentSec: Float = defaultOfflineSegmentSeconds) -> String {
        guard let engine = engine else { return "" }

        qwen_asr_set_segment_sec(engine, segmentSec)
        let resultPtr = samples.withUnsafeBufferPointer { buffer in
            qwen_asr_transcribe_pcm(engine, buffer.baseAddress, Int32(samples.count))
        }
        // Reset segment_sec to avoid affecting streaming behavior
        qwen_asr_set_segment_sec(engine, 0)

        guard let resultPtr = resultPtr else { return "" }
        defer { qwen_asr_free_string(resultPtr) }
        return String(cString: resultPtr)
    }
}

extension QwenASRStreamRecognizer: ASRStreamRecognizing {}
