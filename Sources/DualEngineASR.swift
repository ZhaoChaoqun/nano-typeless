import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "DualEngineASR")

/// 双引擎 ASR：Streaming Paraformer 实时预览 + QwenASR 离线精转写
///
/// 录音过程中：
/// - Streaming Paraformer 流式处理音频，实时输出到 HUD
/// - 音频同时累积到缓冲区，每隔 segmentInterval 秒切分一段送入 QwenASR 离线推理
///
/// 松开 Fn 后：
/// - 仅需处理最后一小段残余音频（之前的段已在后台完成）
/// - 拼接所有段结果作为最终输出
class DualEngineASR: ASREngine {

    // MARK: - 配置

    private static let sampleRate: Int = 16000

    // MARK: - 子引擎

    private let paraformerEngine: StreamingParaformerEngine
    private let qwenRecognizer: QwenASRStreamRecognizer

    // MARK: - 音频缓冲（bufferQueue 保护所有可变状态）

    private let bufferQueue = DispatchQueue(label: "com.typeless.dualengine.buffer")
    private var currentSegmentBuffer: [Float] = []
    private var completedSegments: [String] = []
    private var pendingSegmentCount: Int = 0

    // MARK: - QwenASR 离线推理队列（serial，防止并发访问引擎）

    private let qwenQueue = DispatchQueue(label: "com.typeless.dualengine.qwen", qos: .userInitiated)

    // MARK: - 分段配置

    private let segmentThreshold: Int

    let needsPunctuation = false

    // MARK: - 初始化

    /// - Parameters:
    ///   - paraformerEngine: Streaming Paraformer 引擎（负责实时预览）
    ///   - qwenRecognizer: QwenASR 识别器（负责离线精转写）
    ///   - segmentInterval: 分段间隔（秒），默认 5 秒
    init(paraformerEngine: StreamingParaformerEngine,
         qwenRecognizer: QwenASRStreamRecognizer,
         segmentInterval: TimeInterval = 5.0) {
        self.paraformerEngine = paraformerEngine
        self.qwenRecognizer = qwenRecognizer
        self.segmentThreshold = Int(segmentInterval * Double(DualEngineASR.sampleRate))
        logger.info("DualEngineASR 初始化: 分段间隔 \(segmentInterval)s (\(self.segmentThreshold) samples)")
    }

    // MARK: - ASREngine 协议

    func processAudio(samples: [Float], onPartialResult: @escaping (String, String?) -> Void) {
        // 1. 转发给 Paraformer 做实时预览
        paraformerEngine.processAudio(samples: samples, onPartialResult: onPartialResult)

        // 2. 累积音频用于 QwenASR 分段推理
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentSegmentBuffer.append(contentsOf: samples)

            // 达到分段阈值时，切分并送入 QwenASR
            if self.currentSegmentBuffer.count >= self.segmentThreshold {
                let segmentSamples = self.currentSegmentBuffer
                self.currentSegmentBuffer = []
                self.pendingSegmentCount += 1
                let segmentIndex = self.completedSegments.count + self.pendingSegmentCount - 1

                logger.info("分段 \(segmentIndex): 开始 QwenASR 离线推理 (\(segmentSamples.count) samples)")

                self.qwenQueue.async { [weak self] in
                    guard let self = self else { return }
                    let result = self.qwenRecognizer.transcribeOffline(samples: segmentSamples)
                    self.bufferQueue.async {
                        self.completedSegments.append(result)
                        self.pendingSegmentCount -= 1
                        logger.info("分段 \(segmentIndex): 完成, 结果: \(result.prefix(60), privacy: .public)")
                    }
                }
            }
        }
    }

    func flush(completion: @escaping (String) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            let remainingSamples = self.currentSegmentBuffer
            self.currentSegmentBuffer = []

            logger.info("Flush: 残余音频 \(remainingSamples.count) samples, 已完成分段 \(self.completedSegments.count), 待处理 \(self.pendingSegmentCount)")

            // 在 qwenQueue 上排队，等待所有 pending segment 完成后再处理最后一段
            self.qwenQueue.async { [weak self] in
                guard let self = self else {
                    DispatchQueue.main.async { completion("") }
                    return
                }

                // 处理最后的残余音频
                var finalSegmentResult = ""
                if !remainingSamples.isEmpty {
                    finalSegmentResult = self.qwenRecognizer.transcribeOffline(samples: remainingSamples)
                    logger.info("最后一段推理完成: \(finalSegmentResult.prefix(60), privacy: .public)")
                }

                // 拼接所有段结果
                self.bufferQueue.sync {
                    var allResults = self.completedSegments
                    if !finalSegmentResult.isEmpty {
                        allResults.append(finalSegmentResult)
                    }
                    let finalText = allResults.joined()
                    logger.info("Flush 完成: \(allResults.count) 段, 最终文本: \(finalText.prefix(100), privacy: .public)")

                    DispatchQueue.main.async {
                        completion(finalText)
                    }
                }
            }
        }
    }

    func reset() {
        paraformerEngine.reset()
        bufferQueue.sync {
            currentSegmentBuffer = []
            completedSegments = []
            pendingSegmentCount = 0
        }
    }
}
