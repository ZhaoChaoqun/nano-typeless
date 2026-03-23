import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "PostProcessingPipeline")

/// Coordinates the full post-processing chain: TermNormalizer → ITN → CSC → Punctuation → CloudRewrite.
///
/// Thread safety:
/// - `process(rawText:engine:completion:)` dispatches work to `processingQueue` (serial, userInitiated).
/// - The `completion` closure is called from `processingQueue`; callers should dispatch as needed.
final class PostProcessingPipeline {

    /// Serial queue for CPU-intensive post-processing (ITN, CSC, punctuation).
    let processingQueue: DispatchQueue

    // Post-processing components (set during model initialization)
    var punctuator: SherpaOnnxPunctuation?
    var corrector: ChineseSpellingCorrector?
    var termNormalizer: TermNormalizer?
    var itn: SherpaOnnxITN?

    private let cloudRewriteService = CloudRewriteService()

    init(processingQueue: DispatchQueue) {
        self.processingQueue = processingQueue
    }

    /// Clears all loaded post-processing models.
    /// Called from stateQueue during model reload.
    func reset() {
        punctuator = nil
        corrector = nil
        termNormalizer = nil
        itn = nil
    }

    /// Runs the full post-processing pipeline on the raw ASR text.
    ///
    /// Pipeline stages:
    /// 1. TermNormalizer — domain-specific term standardization
    /// 2. ITN — inverse text normalization (Chinese numbers → Arabic digits), if engine requires it
    /// 3. CSC — Chinese spelling correction, if engine requires punctuation (Paraformer path)
    /// 4. Punctuation — add punctuation marks, if engine requires it
    /// 5. CloudRewrite — LLM-based rewrite for formatting polish
    ///
    /// - Parameters:
    ///   - rawText: The raw text from ASR engine flush.
    ///   - engine: The current ASR engine (used to check `needsITN` / `needsPunctuation`).
    ///   - completion: Called on `processingQueue` with the final text (nil if empty input).
    func process(rawText: String, engine: (any ASREngine)?, completion: @escaping (String?) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let pipelineStart = ContinuousClock.now

            guard !rawText.isEmpty else {
                logger.info("最终识别结果: （无）")
                completion(nil)
                return
            }

            // Stage 1: Term normalization (domain-specific)
            let termNormStart = ContinuousClock.now
            let normalizedText = self.termNormalizer?.normalize(rawText) ?? rawText
            let termNormMs = AnalyticsService.elapsedMs(since: termNormStart)
            let termNormChanged = normalizedText != rawText
            if termNormChanged {
                logger.info("TermNormalizer: \(rawText, privacy: .public) → \(normalizedText, privacy: .public)")
            }

            // Stage 2: ITN (inverse text normalization) for engines that need it
            var processedText = normalizedText
            let itnApplied: Bool
            let itnMs: Int
            if let engine = engine, engine.needsITN, let itn = self.itn {
                let itnStart = ContinuousClock.now
                let before = processedText
                processedText = itn.normalize(text: processedText)
                itnMs = AnalyticsService.elapsedMs(since: itnStart)
                itnApplied = processedText != before
                if itnApplied {
                    logger.info("ITN: \(normalizedText, privacy: .public) → \(processedText, privacy: .public)")
                }
            } else {
                itnApplied = false
                itnMs = 0
            }

            // Branch: engines that don't need punctuation skip CSC + punctuation
            guard let engine = engine, engine.needsPunctuation else {
                Task { [weak self] in
                    guard let self else { return }
                    let cloudRewriteStart = ContinuousClock.now
                    let rewrittenText = await self.cloudRewriteService.rewriteOrPassthrough(processedText)
                    let cloudRewriteMs = AnalyticsService.elapsedMs(since: cloudRewriteStart)
                    self.processingQueue.async {
                        let totalMs = AnalyticsService.elapsedMs(since: pipelineStart)
                        AnalyticsService.track("PostProcessing.Completed", parameters: [
                            "itnApplied": "\(itnApplied)",
                            "cscApplied": "false",
                            "punctuationApplied": "false",
                            "totalLatencyMs": "\(totalMs)",
                            "termNormLatencyMs": "\(termNormMs)",
                            "itnLatencyMs": "\(itnMs)",
                            "cscLatencyMs": "0",
                            "punctLatencyMs": "0",
                            "cloudRewriteLatencyMs": "\(cloudRewriteMs)",
                            "termNormChanged": "\(termNormChanged)",
                        ])
                        logger.info("最终结果: \(rewrittenText, privacy: .public)")
                        completion(rewrittenText)
                    }
                }
                return
            }

            // Stage 3: CSC (Chinese spelling correction)
            let cscStart = ContinuousClock.now
            let correctedText = self.corrector?.correctSpelling(processedText) ?? processedText
            let cscMs = AnalyticsService.elapsedMs(since: cscStart)
            let cscApplied = correctedText != processedText
            logger.info("原始文本: \(processedText, privacy: .public)")
            if cscApplied {
                logger.info("CSC 纠正: \(correctedText, privacy: .public)")
            } else {
                logger.info("CSC 未修改文本")
            }

            // Stage 4: Punctuation
            let punctStart = ContinuousClock.now
            let punctuatedText = self.punctuator?.addPunctuation(text: correctedText) ?? correctedText
            let punctMs = AnalyticsService.elapsedMs(since: punctStart)
            let punctuationApplied = punctuatedText != correctedText
            logger.info("标点处理后: \(punctuatedText, privacy: .public)")

            // Stage 5: Cloud rewrite
            Task { [weak self] in
                guard let self else { return }
                let cloudRewriteStart = ContinuousClock.now
                let rewrittenText = await self.cloudRewriteService.rewriteOrPassthrough(punctuatedText)
                let cloudRewriteMs = AnalyticsService.elapsedMs(since: cloudRewriteStart)
                self.processingQueue.async {
                    let totalMs = AnalyticsService.elapsedMs(since: pipelineStart)
                    AnalyticsService.track("PostProcessing.Completed", parameters: [
                        "itnApplied": "\(itnApplied)",
                        "cscApplied": "\(cscApplied)",
                        "punctuationApplied": "\(punctuationApplied)",
                        "totalLatencyMs": "\(totalMs)",
                        "termNormLatencyMs": "\(termNormMs)",
                        "itnLatencyMs": "\(itnMs)",
                        "cscLatencyMs": "\(cscMs)",
                        "punctLatencyMs": "\(punctMs)",
                        "cloudRewriteLatencyMs": "\(cloudRewriteMs)",
                        "termNormChanged": "\(termNormChanged)",
                    ])
                    completion(rewrittenText)
                }
            }
        }
    }
}
