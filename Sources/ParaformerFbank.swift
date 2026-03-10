import Accelerate
import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "Fbank")

/// 80-dim log-mel filterbank 特征提取器（Accelerate + vDSP）
///
/// 参数与 kaldi/sherpa-onnx 完全一致：
///   sample_rate = 16000, frame_length = 25ms (400 samples),
///   frame_shift = 10ms (160 samples), num_mel_bins = 80,
///   window = hamming, dither = 0, snip_edges = true,
///   NFFT = 512, mel freq range = [20, 8000] Hz
///
/// 注意：输入 samples 应为 int16 范围（即 float32 值域 [-32768, 32768]），
/// 与 sherpa-onnx 的 normalize_samples=false 一致。
class ParaformerFbank {
    // MARK: - 常量

    private let sampleRate: Int = 16000
    private let frameLengthSamples: Int = 400   // 25ms * 16000
    private let frameShiftSamples: Int = 160    // 10ms * 16000
    private let nMelBins: Int = 80
    private let nfft: Int = 512                 // 最小的 2^n >= 400
    private let fftHalfSize: Int = 257          // nfft/2 + 1

    // MARK: - 预计算数据

    /// Hamming 窗 [400]
    private let window: [Float]

    /// Mel 滤波器矩阵 [80 * 257] — row-major, 每行 257 对应一个 mel bin
    private let melFilterbank: [Float]

    /// vDSP FFT setup (for real FFT, log2n = log2(512) = 9)
    private let fftSetup: FFTSetup

    // MARK: - 流式状态

    /// 累积的 PCM samples
    private var sampleBuffer: [Float] = []

    /// 是否已标记输入结束
    private var isFinished: Bool = false

    /// 已提取的帧（每帧 80-dim）
    private var frames: [[Float]] = []

    // MARK: - 初始化

    init() {
        // 1. Hamming 窗
        var win = [Float](repeating: 0, count: frameLengthSamples)
        vDSP_hamm_window(&win, vDSP_Length(frameLengthSamples), 0)  // 0 = full window
        self.window = win

        // 2. FFT setup (log2(512) = 9) — using vDSP_fft_zrip (real in-place FFT)
        guard let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else {
            fatalError("ParaformerFbank: 无法创建 FFT setup")
        }
        self.fftSetup = setup

        // 3. Mel 滤波器组
        self.melFilterbank = ParaformerFbank.buildMelFilterbank(
            numMelBins: 80,
            nfft: 512,
            sampleRate: 16000,
            lowFreq: 20.0,
            highFreq: 8000.0
        )
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - 流式接口

    /// 接收 PCM samples（int16 范围的 float32）
    func acceptWaveform(samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        extractPendingFrames()
    }

    /// 标记输入结束
    func inputFinished() {
        isFinished = true
        // snip_edges=true: 不额外处理不足一帧的尾部
    }

    /// 当前可用的帧数
    var numFramesReady: Int {
        return frames.count
    }

    /// 获取第 index 帧的特征（80-dim）
    func getFrame(_ index: Int) -> [Float] {
        guard index >= 0 && index < frames.count else {
            return [Float](repeating: 0, count: nMelBins)
        }
        return frames[index]
    }

    /// 获取从 startIndex 开始的所有帧，拼成 [T, 80] flat array
    func getFrames(from startIndex: Int) -> [Float] {
        guard startIndex < frames.count else { return [] }
        var result = [Float]()
        result.reserveCapacity((frames.count - startIndex) * nMelBins)
        for i in startIndex..<frames.count {
            result.append(contentsOf: frames[i])
        }
        return result
    }

    /// 重置全部状态
    func reset() {
        sampleBuffer.removeAll()
        isFinished = false
        frames.removeAll()
    }

    // MARK: - 批量接口

    /// 一次性计算所有帧，返回 [T, 80] flat array
    func compute(samples: [Float]) -> [Float] {
        reset()
        sampleBuffer = samples
        isFinished = true
        extractPendingFrames()

        var result = [Float]()
        result.reserveCapacity(frames.count * nMelBins)
        for frame in frames {
            result.append(contentsOf: frame)
        }
        return result
    }

    // MARK: - 内部方法

    /// 从 sampleBuffer 中提取所有可用帧
    private func extractPendingFrames() {
        // snip_edges=true: 只有完整帧才提取
        // 帧数 = (len - frameLengthSamples) / frameShiftSamples + 1
        let totalSamples = sampleBuffer.count
        guard totalSamples >= frameLengthSamples else { return }

        let startFrame = frames.count
        let numPossibleFrames = (totalSamples - frameLengthSamples) / frameShiftSamples + 1

        guard numPossibleFrames > startFrame else { return }

        // 临时缓冲区（复用以减少分配）
        // For vDSP_fft_zrip: input is N real values packed as N/2 complex pairs
        // realp[k] = x[2k], imagp[k] = x[2k+1], k = 0..N/2-1
        let halfN = nfft / 2  // 256
        var splitReal = [Float](repeating: 0, count: halfN)
        var splitImag = [Float](repeating: 0, count: halfN)
        var powerSpectrum = [Float](repeating: 0, count: fftHalfSize)
        var melEnergies = [Float](repeating: 0, count: nMelBins)
        var paddedInput = [Float](repeating: 0, count: nfft)

        var frameBuf = [Float](repeating: 0, count: frameLengthSamples)

        for frameIdx in startFrame..<numPossibleFrames {
            let offset = frameIdx * frameShiftSamples

            // 1a. 取帧
            for i in 0..<frameLengthSamples {
                frameBuf[i] = sampleBuffer[offset + i]
            }

            // 1b. Remove DC offset（减去帧内均值，与 kaldi remove_dc_offset=true 一致）
            var mean: Float = 0
            vDSP_meanv(frameBuf, 1, &mean, vDSP_Length(frameLengthSamples))
            var negMean = -mean
            vDSP_vsadd(frameBuf, 1, &negMean, &frameBuf, 1, vDSP_Length(frameLengthSamples))

            // 1c. Pre-emphasis: y[n] = x[n] - 0.97 * x[n-1]（与 kaldi preemph_coeff=0.97 一致）
            let preemphCoeff: Float = 0.97
            for i in stride(from: frameLengthSamples - 1, through: 1, by: -1) {
                frameBuf[i] -= preemphCoeff * frameBuf[i - 1]
            }
            frameBuf[0] -= preemphCoeff * frameBuf[0]  // kaldi: first sample *= (1 - preemph)

            // 1d. 加窗 + 零填充
            frameBuf.withUnsafeBufferPointer { srcBuf in
                window.withUnsafeBufferPointer { winBuf in
                    paddedInput.withUnsafeMutableBufferPointer { padBuf in
                        vDSP_vmul(
                            srcBuf.baseAddress!, 1,
                            winBuf.baseAddress!, 1,
                            padBuf.baseAddress!, 1,
                            vDSP_Length(frameLengthSamples)
                        )
                        // 零填充 400..<512
                        for i in frameLengthSamples..<nfft {
                            padBuf[i] = 0
                        }
                    }
                }
            }

            // 2. Pack into even-odd split complex format for vDSP_fft_zrip
            for k in 0..<halfN {
                splitReal[k] = paddedInput[2 * k]
                splitImag[k] = paddedInput[2 * k + 1]
            }

            // 3. In-place real FFT
            splitReal.withUnsafeMutableBufferPointer { realBuf in
                splitImag.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuf.baseAddress!,
                        imagp: imagBuf.baseAddress!
                    )
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, 9, FFTDirection(kFFTDirection_Forward))

                    // 4. Scale by 1/2 (vDSP real FFT has 2x factor)
                    var scale: Float = 0.5
                    vDSP_vsmul(realBuf.baseAddress!, 1, &scale, realBuf.baseAddress!, 1, vDSP_Length(halfN))
                    vDSP_vsmul(imagBuf.baseAddress!, 1, &scale, imagBuf.baseAddress!, 1, vDSP_Length(halfN))
                }
            }

            // 5. Unpack to power spectrum [0..N/2] = 257 bins
            // After zrip + scale:
            //   splitReal[0] = X[0].real (DC, imaginary is 0)
            //   splitImag[0] = X[N/2].real (Nyquist, imaginary is 0)
            //   splitReal[k], splitImag[k] = X[k].real, X[k].imag for k=1..N/2-1
            powerSpectrum[0] = splitReal[0] * splitReal[0]  // DC: imag=0
            for k in 1..<halfN {
                powerSpectrum[k] = splitReal[k] * splitReal[k] + splitImag[k] * splitImag[k]
            }
            powerSpectrum[halfN] = splitImag[0] * splitImag[0]  // Nyquist: imag=0

            // 6. Mel 滤波: melEnergies = melFilterbank × powerSpectrum
            //    melFilterbank 是 [80, 257], powerSpectrum 是 [257]
            //    输出 melEnergies [80]
            melFilterbank.withUnsafeBufferPointer { melBuf in
                powerSpectrum.withUnsafeBufferPointer { powBuf in
                    melEnergies.withUnsafeMutableBufferPointer { outBuf in
                        vDSP_mmul(
                            melBuf.baseAddress!, 1,
                            powBuf.baseAddress!, 1,
                            outBuf.baseAddress!, 1,
                            vDSP_Length(nMelBins),    // M (rows of A)
                            1,                         // N (cols of B)
                            vDSP_Length(fftHalfSize)   // K (cols of A = rows of B)
                        )
                    }
                }
            }

            // 7. Log: log(max(energy, epsilon))
            let epsilon: Float = 1.1920929e-7  // FLT_EPSILON (与 kaldi-native-fbank 一致)
            for i in 0..<nMelBins {
                melEnergies[i] = logf(max(melEnergies[i], epsilon))
            }

            frames.append(melEnergies)
        }
    }

    // MARK: - Mel 滤波器组构建

    /// 构建 mel 三角滤波器组 [numMelBins, nfft/2+1]
    ///
    /// 使用 HTK mel 频率标度（与 kaldi 默认一致）:
    ///   mel(f) = 1127 * ln(1 + f/700)
    ///   f(mel) = 700 * (exp(mel/1127) - 1)
    private static func buildMelFilterbank(
        numMelBins: Int,
        nfft: Int,
        sampleRate: Int,
        lowFreq: Float,
        highFreq: Float
    ) -> [Float] {
        let halfSize = nfft / 2 + 1
        let sr = Float(sampleRate)

        // Hz → Mel 转换
        func hzToMel(_ hz: Float) -> Float {
            return 1127.0 * logf(1.0 + hz / 700.0)
        }
        func melToHz(_ mel: Float) -> Float {
            return 700.0 * (expf(mel / 1127.0) - 1.0)
        }

        let melLow = hzToMel(lowFreq)
        let melHigh = hzToMel(highFreq)

        // numMelBins + 2 个均匀分布的 mel 点
        var melPoints = [Float](repeating: 0, count: numMelBins + 2)
        for i in 0...(numMelBins + 1) {
            melPoints[i] = melLow + Float(i) * (melHigh - melLow) / Float(numMelBins + 1)
        }

        // mel 点转回 Hz，然后转为 FFT bin 索引（浮点）
        let binFreqs = melPoints.map { melToHz($0) }
        let binIndices = binFreqs.map { $0 * Float(nfft) / sr }

        // 构建滤波器矩阵 [numMelBins, halfSize]
        var filterbank = [Float](repeating: 0, count: numMelBins * halfSize)

        for m in 0..<numMelBins {
            let left = binIndices[m]
            let center = binIndices[m + 1]
            let right = binIndices[m + 2]

            for k in 0..<halfSize {
                let fk = Float(k)
                if fk > left && fk <= center {
                    filterbank[m * halfSize + k] = (fk - left) / (center - left)
                } else if fk > center && fk < right {
                    filterbank[m * halfSize + k] = (right - fk) / (right - center)
                }
            }
        }

        return filterbank
    }
}
