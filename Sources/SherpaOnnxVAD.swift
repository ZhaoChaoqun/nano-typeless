import Foundation

/// Sherpa-ONNX VAD（语音活动检测）
class SherpaOnnxVAD {
    private var vad: OpaquePointer?
    private let sampleRate: Int32 = 16000

    /// 初始化 VAD
    init?(modelPath: String) {
        print(">>> SherpaOnnxVAD: 开始初始化...")
        print("    模型路径: \(modelPath)")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            print(">>> SherpaOnnxVAD: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxVadModelConfig()

        // Silero VAD 配置
        config.silero_vad.model = toCString(modelPath)
        config.silero_vad.threshold = 0.5           // 语音检测阈值
        config.silero_vad.min_silence_duration = 0.5 // 最小静音时长（秒），用于分段
        config.silero_vad.min_speech_duration = 0.1  // 最小语音时长（秒），过滤噪音
        config.silero_vad.max_speech_duration = 15.0 // 最大语音时长（秒）
        config.silero_vad.window_size = 512          // 窗口大小

        config.sample_rate = sampleRate
        config.num_threads = 2
        config.provider = toCString("cpu")
        config.debug = 0

        // 创建 VAD 检测器，5秒缓冲区
        vad = SherpaOnnxCreateVoiceActivityDetector(&config, 5.0)

        if vad == nil {
            print(">>> SherpaOnnxVAD: 创建 VAD 失败")
            return nil
        }

        print(">>> SherpaOnnxVAD: 初始化成功")
    }

    deinit {
        if let vad = vad {
            SherpaOnnxDestroyVoiceActivityDetector(vad)
        }
    }

    /// 输入音频样本
    func acceptWaveform(samples: [Float]) {
        guard let vad = vad else { return }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, buffer.baseAddress, Int32(samples.count))
        }
    }

    /// 检查是否有可用的语音段
    func hasSegment() -> Bool {
        guard let vad = vad else { return false }
        return SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0
    }

    /// 检测当前是否有语音
    func isDetected() -> Bool {
        guard let vad = vad else { return false }
        return SherpaOnnxVoiceActivityDetectorDetected(vad) == 1
    }

    /// 获取并移除第一个语音段
    func popSegment() -> [Float]? {
        guard let vad = vad else { return nil }
        guard hasSegment() else { return nil }

        guard let segment = SherpaOnnxVoiceActivityDetectorFront(vad) else {
            return nil
        }

        defer {
            SherpaOnnxDestroySpeechSegment(segment)
            SherpaOnnxVoiceActivityDetectorPop(vad)
        }

        let count = Int(segment.pointee.n)
        guard count > 0, let samplesPtr = segment.pointee.samples else {
            return nil
        }

        // 复制样本数据
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = samplesPtr[i]
        }

        return samples
    }

    /// 刷新缓冲区，处理剩余数据
    func flush() {
        guard let vad = vad else { return }
        SherpaOnnxVoiceActivityDetectorFlush(vad)
    }

    /// 重置 VAD 状态
    func reset() {
        guard let vad = vad else { return }
        SherpaOnnxVoiceActivityDetectorReset(vad)
    }

    /// 清空所有语音段
    func clear() {
        guard let vad = vad else { return }
        SherpaOnnxVoiceActivityDetectorClear(vad)
    }

    // MARK: - Private

    private func toCString(_ string: String) -> UnsafePointer<CChar>? {
        return UnsafePointer(strdup(string))
    }
}
