import Foundation
import AVFoundation

/// 管理音频录制和语音识别
class RecordingManager {
    static let shared = RecordingManager()

    private var audioEngine: AVAudioEngine?
    private var recognizer: SherpaOnnxRecognizer?
    private var vad: SherpaOnnxVAD?
    private var isRecording = false
    private var isInitializing = false

    /// 部分识别结果回调
    var onPartialResult: ((String) -> Void)?
    /// 累积的识别文字
    private var accumulatedText: String = ""
    /// 用于识别的队列
    private let recognitionQueue = DispatchQueue(label: "com.typeless.recognition", qos: .userInitiated)

    init() {
        Task { await initializeRecognizer() }
    }

    private func initializeRecognizer() async {
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        print("========== 开始加载语音识别模型 ==========")

        guard SherpaOnnxManager.shared.isModelDownloaded(),
              let paths = SherpaOnnxManager.shared.getModelPath() else {
            print("⚠️ 模型未下载")
            return
        }

        recognizer = SherpaOnnxRecognizer(modelPath: paths.modelPath, tokensPath: paths.tokensPath)

        if recognizer != nil {
            print("========== 模型加载成功 ==========")
        } else {
            print("========== 模型加载失败 ==========")
        }

        // 初始化 VAD
        await initializeVAD()
    }

    private func initializeVAD() async {
        // 先检查 VAD 模型是否存在
        if let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
            vad = SherpaOnnxVAD(modelPath: vadPath)
            if vad != nil {
                print("========== VAD 加载成功 ==========")
            }
        } else {
            print("⚠️ VAD 模型未下载，正在下载...")
            // 异步下载 VAD 模型
            await withCheckedContinuation { continuation in
                SherpaOnnxManager.shared.downloadVADModel(progress: { progress in
                    print("[VAD] \(progress)")
                }, completion: { [weak self] success, error in
                    if success, let vadPath = SherpaOnnxManager.shared.getVADModelPath() {
                        self?.vad = SherpaOnnxVAD(modelPath: vadPath)
                        print("========== VAD 下载并加载成功 ==========")
                    } else {
                        print("⚠️ VAD 下载失败: \(error ?? "未知错误")")
                    }
                    continuation.resume()
                })
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        // 重置状态
        accumulatedText = ""
        vad?.reset()

        // 创建音频引擎
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 目标格式：16kHz, mono, float32
        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            print("无法创建目标音频格式")
            return
        }

        // 创建格式转换器
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("无法创建音频转换器")
            return
        }

        // 安装音频 tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            isRecording = true
            print("开始流式录音")
        } catch {
            print("启动音频引擎失败: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        guard let vad = vad else { return }

        // 计算输出缓冲区大小
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

        // 转换音频格式
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("音频转换错误: \(error)")
            return
        }

        // 提取浮点样本
        guard let floatData = outputBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))

        // 送入 VAD
        vad.acceptWaveform(samples: samples)

        // 检查是否有完整的语音段
        while vad.hasSegment() {
            if let segment = vad.popSegment() {
                recognitionQueue.async { [weak self] in
                    self?.transcribeSegment(segment)
                }
            }
        }
    }

    private func transcribeSegment(_ samples: [Float]) {
        guard let recognizer = recognizer else { return }

        if let text = recognizer.transcribe(samples: samples) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // 智能拼接文字（去除重叠）
                self.accumulatedText = self.mergeTexts(self.accumulatedText, text)

                print(">>> 分段识别结果: \(text)")
                print(">>> 累积文字: \(self.accumulatedText)")

                // 通知 UI 更新
                self.onPartialResult?(self.accumulatedText)
            }
        }
    }

    /// 智能拼接文字，去除重叠部分
    private func mergeTexts(_ existing: String, _ new: String) -> String {
        guard !existing.isEmpty, !new.isEmpty else {
            return existing + new
        }

        // 查找最长重叠（最多检查 10 个字符）
        let maxOverlap = min(existing.count, new.count, 10)

        for overlapLen in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = String(existing.suffix(overlapLen))
            let prefix = String(new.prefix(overlapLen))

            if suffix == prefix {
                // 找到重叠，去除 new 的重叠前缀
                print(">>> 检测到重叠: \"\(suffix)\"，已去除")
                return existing + String(new.dropFirst(overlapLen))
            }
        }

        // 无重叠，直接拼接（无空格，因为中文不需要）
        return existing + new
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        // 停止音频引擎
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        print("停止录音")

        // 刷新 VAD，处理剩余音频
        vad?.flush()

        // 处理剩余的语音段
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            while self.vad?.hasSegment() == true {
                if let segment = self.vad?.popSegment() {
                    if let text = self.recognizer?.transcribe(samples: segment) {
                        DispatchQueue.main.sync {
                            // 智能拼接文字（去除重叠）
                            self.accumulatedText = self.mergeTexts(self.accumulatedText, text)
                        }
                    }
                }
            }

            // 返回最终结果
            let finalText = self.accumulatedText.isEmpty ? nil : self.accumulatedText
            DispatchQueue.main.async {
                print(">>> 最终识别结果: \(finalText ?? "（无）")")
                completion(finalText)
            }
        }
    }

    var isInitialized: Bool {
        return recognizer != nil
    }

    /// 重新加载模型（下载完成后调用）
    func reloadModel() {
        recognizer = nil
        vad = nil
        Task { await initializeRecognizer() }
    }
}
