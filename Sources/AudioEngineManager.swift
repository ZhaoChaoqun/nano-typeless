import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "AudioEngineManager")

/// Manages AVAudioEngine lifecycle: setup, tap installation, start/stop, and buffer-to-samples conversion.
///
/// Thread safety:
/// - `start()` and `stop()` are called from `stateQueue` (via RecordingManager side effects).
/// - The `installTap` callback fires on an internal Core Audio thread; the `onSamples` closure
///   must handle its own synchronization.
final class AudioEngineManager {

    /// Callback invoked with 16kHz Float32 mono samples from the microphone.
    /// Called on a Core Audio thread — callers must dispatch to appropriate queues.
    var onSamples: (([Float]) -> Void)?

    /// Callback invoked with normalized audio level (0.0–1.0).
    /// Called on the main queue.
    var onAudioLevel: ((Float) -> Void)?

    private var audioEngine: AVAudioEngine?

    // MARK: - Public API

    /// Creates a new AVAudioEngine, installs a tap, and starts capturing audio.
    /// Called from stateQueue.
    func start() {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetSampleRate: Double = 16000
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("无法创建目标音频格式")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            logger.error("无法创建音频转换器")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let samples = self.extractSamples(buffer: buffer, converter: converter, targetFormat: targetFormat) else {
                return
            }

            // Calculate RMS audio level and notify UI
            if let onAudioLevel = self.onAudioLevel {
                var sum: Float = 0
                for s in samples { sum += s * s }
                let rms = sqrt(sum / max(Float(samples.count), 1))
                let db = 20 * log10(max(rms, 1e-6))
                let normalized = max(0, min(1, (db + 50) / 50))
                DispatchQueue.main.async {
                    onAudioLevel(normalized)
                }
            }

            self.onSamples?(samples)
        }

        do {
            try engine.start()
            logger.info("音频引擎已启动")
        } catch {
            logger.error("启动音频引擎失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the tap, stops the engine, and releases resources.
    /// Called from stateQueue.
    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        logger.info("音频引擎已停止")
    }

    // MARK: - Private

    /// Converts an AVAudioPCMBuffer to 16kHz Float32 mono samples.
    private func extractSamples(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Float]? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("音频转换错误: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let floatData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
    }
}
