import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "QwenASR")

/// QwenASR 流式识别器
/// 每次推送新音频 chunk，增量返回识别结果
class QwenASRStreamRecognizer {
    private var engine: OpaquePointer?       // QwenAsrEngine*
    private var streamState: OpaquePointer?  // QwenAsrStreamState*

    init?(modelDir: String, numThreads: Int32 = 4) {
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

        // 流式参数：chunk_sec 和 max_new_tokens 保持默认以获得更好的准确度
        // rollback 和 unfixed_chunks 适度降低以减少首字延迟
        qwen_asr_stream_set_chunk_sec(engine, 1.5)
        qwen_asr_stream_set_rollback(engine, 3)
        qwen_asr_stream_set_unfixed_chunks(engine, 1)
        qwen_asr_stream_set_max_new_tokens(engine, 32)

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
    func transcribeOffline(samples: [Float], segmentSec: Float = 20.0) -> String {
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
