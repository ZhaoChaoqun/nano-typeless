import XCTest
@testable import Nano_Typeless

/// ASR Pipeline Benchmark — 直接使用产品 Swift 代码评估 5 个 Pipeline
///
/// Pipeline:
///   1. Qwen3-ASR (离线): pushAudio(finalize:true) 一次性识别
///   2. Qwen3-ASR (流式): chunk+rollback 模拟流式
///   3. Paraformer Pipeline: Streaming Paraformer + ITN → CSC → CT-Transformer 标点
///   4. FunASR Nano LLM Pipeline: SenseVoice encoder + Qwen3 LLM + VAD（自带标点）
///
/// 运行:
///   xcodebuild test -scheme Typeless -destination 'platform=macOS' \
///     -only-testing:TypelessTests/ASRPipelineBenchmarkTests
class ASRPipelineBenchmarkTests: XCTestCase {

    // MARK: - 共享状态

    static var entries: [BenchmarkEntry] = []
    static var fixturesPath = ""

    // Pipeline 组件
    static var qwenRecognizer: QwenASRStreamRecognizer?
    static var paraformerRecognizer: SherpaOnnxOnlineRecognizer?
    static var funasrNanoLLMRecognizer: FunASRNanoLLMRecognizer?
    static var vad: SherpaOnnxVAD?
    static var punctuator: SherpaOnnxPunctuation?
    static var corrector: ChineseSpellingCorrector?

    // 可用性标记
    static var qwenAvailable = false
    static var paraformerAvailable = false
    static var funasrNanoLLMAvailable = false

    // 日志文件
    static var logPath: String = ""
    static var logHandle: FileHandle?

    /// 同时输出到 print() 和日志文件
    static func log(_ message: String = "") {
        print(message)
        if let handle = logHandle {
            if let data = (message + "\n").data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    // 结果存储（供报告聚合）
    struct PipelineResult {
        let pipelineName: String
        let results: [(id: String, category: String, expected: String, actual: String, cer: Double, elapsed: Double)]
    }
    static var allResults: [PipelineResult] = []

    // MARK: - Setup / Teardown

    override class func setUp() {
        super.setUp()

        // 初始化日志文件
        let ts = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return f.string(from: Date())
        }()
        logPath = NSTemporaryDirectory() + "benchmark_swift_\(ts).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        logHandle = FileHandle(forWritingAtPath: logPath)
        log("[Benchmark] 日志文件: \(logPath)")

        fixturesPath = TestEnvironment.fixturesPath()
        var allEntries = BenchmarkEntryLoader.loadAll(fixturesPath: fixturesPath)

        // 支持通过环境变量 BENCHMARK_ENTRY 或临时文件筛选条目（逗号分隔多个 ID）
        //   用法: echo "ascend_cs_003,zh_short_01" > /tmp/benchmark_entry_filter.txt
        //   或:   BENCHMARK_ENTRY=ascend_cs_003 xcodebuild test ...
        let entryFilter: String? = {
            // 优先读环境变量
            if let env = ProcessInfo.processInfo.environment["BENCHMARK_ENTRY"], !env.isEmpty {
                return env
            }
            // 其次读临时文件
            let filterFile = "/tmp/benchmark_entry_filter.txt"
            if let content = try? String(contentsOfFile: filterFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return content
            }
            return nil
        }()

        if let filter = entryFilter {
            let ids = Set(filter.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            allEntries = allEntries.filter { ids.contains($0.id) }
            log("[Benchmark] 筛选条目: \(ids.sorted().joined(separator: ", "))")
        }

        entries = allEntries
        log("[Benchmark] 加载 \(entries.count) 条测试条目")

        // Qwen3-ASR
        if let dir = TestEnvironment.qwenModelDirectory() {
            qwenRecognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4)
            qwenAvailable = qwenRecognizer != nil
            log("[Benchmark] Qwen3-ASR: \(qwenAvailable ? "✓" : "✗")")
        }

        // Paraformer
        if let paths = TestEnvironment.paraformerPaths() {
            let itnPath = TestEnvironment.itnFstPath()
            paraformerRecognizer = SherpaOnnxOnlineRecognizer(
                encoderPath: paths.encoder,
                decoderPath: paths.decoder,
                tokensPath: paths.tokens,
                ruleFstsPath: itnPath
            )
            paraformerAvailable = paraformerRecognizer != nil
            log("[Benchmark] Paraformer: \(paraformerAvailable ? "✓" : "✗") (ITN: \(itnPath != nil ? "on" : "off"))")
        }

        // FunASR Nano LLM
        if let paths = TestEnvironment.funasrNanoLLMPaths() {
            funasrNanoLLMRecognizer = FunASRNanoLLMRecognizer(
                encoderAdaptorPath: paths.encoderAdaptor,
                llmPath: paths.llm,
                embeddingPath: paths.embedding,
                tokenizerDir: paths.tokenizerDir
            )
            funasrNanoLLMAvailable = funasrNanoLLMRecognizer != nil
            log("[Benchmark] FunASR Nano LLM: \(funasrNanoLLMAvailable ? "✓" : "✗")")
        }

        // CSC
        if let cscPaths = TestEnvironment.cscModelPaths() {
            corrector = ChineseSpellingCorrector(modelPath: cscPaths.model, vocabPath: cscPaths.vocab)
            log("[Benchmark] CSC: \(corrector != nil ? "✓" : "✗")")
        }

        // 标点
        if let punctPath = TestEnvironment.punctuationModelPath() {
            punctuator = SherpaOnnxPunctuation(modelPath: punctPath)
            log("[Benchmark] 标点: \(punctuator != nil ? "✓" : "✗")")
        }
    }

    override class func tearDown() {
        log("[Benchmark] 完成。日志已保存到: \(logPath)")
        logHandle?.closeFile()
        logHandle = nil
        qwenRecognizer = nil
        paraformerRecognizer = nil
        funasrNanoLLMRecognizer = nil
        vad = nil
        punctuator = nil
        corrector = nil
        super.tearDown()
    }

    // MARK: - Pipeline Tests

    func testQwenASROfflinePipeline() throws {
        try XCTSkipUnless(Self.qwenAvailable, "Qwen3-ASR 模型不可用")
        let recognizer = Self.qwenRecognizer!

        let results = runPipeline(name: "Qwen3-ASR (离线)") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples
            return recognizer.transcribeOffline(samples: samples)
        }

        Self.allResults.append(PipelineResult(pipelineName: "Qwen3-ASR (离线)", results: results))
    }

    func testQwenASRStreamPipeline() throws {
        try XCTSkipUnless(Self.qwenAvailable, "Qwen3-ASR 模型不可用")
        // 流式需要独立的 recognizer 实例，避免与离线共享状态冲突
        guard let dir = TestEnvironment.qwenModelDirectory(),
              let recognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4) else {
            throw XCTSkip("Qwen3-ASR 流式 recognizer 创建失败")
        }

        let results = runPipeline(name: "Qwen3-ASR (流式)") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples
            recognizer.reset()

            // 模拟流式：2 秒 chunk
            let chunkSize = 32000  // 2s @ 16kHz
            var offset = 0
            while offset < samples.count {
                let end = min(offset + chunkSize, samples.count)
                let chunk = Array(samples[offset..<end])
                _ = recognizer.pushAudio(samples: chunk, finalize: false)
                offset = end
            }
            // 直接取 stable + unfixed 作为最终结果，与产品代码 QwenASREngine.flush() 一致
            // 避免推送 silence+finalize 导致 decoder 在静音上 hallucinate 重复文本
            let stableText = recognizer.getResult()
            let unfixedText = recognizer.getUnfixed() ?? ""
            return stableText + unfixedText
        }

        Self.allResults.append(PipelineResult(pipelineName: "Qwen3-ASR (流式)", results: results))
    }

    func testParaformerPipeline() throws {
        try XCTSkipUnless(Self.paraformerAvailable, "Paraformer 模型不可用")
        let recognizer = Self.paraformerRecognizer!

        let results = runPipeline(name: "Paraformer Pipeline") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples
            recognizer.reset()

            // 逐 chunk 送入并解码（与产品代码一致）
            let chunkSize = 4096
            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                recognizer.acceptWaveform(samples: chunk)
                while recognizer.isReady() {
                    recognizer.decode()
                }
            }

            // 1s silence padding + inputFinished 确保流式解码器完成尾部帧
            let silencePadding = [Float](repeating: 0.0, count: 16000)
            recognizer.acceptWaveform(samples: silencePadding)
            while recognizer.isReady() {
                recognizer.decode()
            }

            recognizer.inputFinished()
            while recognizer.isReady() {
                recognizer.decode()
            }

            var text = recognizer.getResult()
            recognizer.reset()

            // 后处理：CSC → 标点
            text = Self.applyPostProcessing(text)
            return text
        }

        Self.allResults.append(PipelineResult(pipelineName: "Paraformer Pipeline", results: results))
    }

    func testFunASRNanoLLMPipeline() throws {
        try XCTSkipUnless(Self.funasrNanoLLMAvailable, "FunASR Nano LLM 模型不可用")
        let recognizer = Self.funasrNanoLLMRecognizer!

        // FunASR Nano LLM 是离线模型，长音频需要 VAD 分段
        // 短音频（< 30s）可直接整段识别；长音频必须 VAD 分段后逐段识别
        let vadForLLM: SherpaOnnxVAD? = {
            guard let vadPath = TestEnvironment.vadModelPath() else { return nil }
            return SherpaOnnxVAD(modelPath: vadPath)
        }()

        let results = runPipeline(name: "FunASR Nano LLM") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples

            // 长音频（≥ 25s）使用 VAD 分段识别
            if samples.count >= 25 * 16000, let vad = vadForLLM {
                vad.reset()

                // VAD 需要按 chunk 送入（内部缓冲区有限），与产品代码 installTap 的行为一致
                let chunkSize = 4096
                var accumulated = ""
                var segCount = 0

                for i in stride(from: 0, to: samples.count, by: chunkSize) {
                    let end = min(i + chunkSize, samples.count)
                    let chunk = Array(samples[i..<end])
                    vad.acceptWaveform(samples: chunk)

                    while vad.hasSegment() {
                        if let segment = vad.popSegmentWithTime() {
                            segCount += 1
                            if let text = recognizer.transcribe(samples: segment.samples) {
                                accumulated += text
                            }
                        }
                    }
                }

                vad.flush()
                while vad.hasSegment() {
                    if let segment = vad.popSegmentWithTime() {
                        segCount += 1
                        if let text = recognizer.transcribe(samples: segment.samples) {
                            accumulated += text
                        }
                    }
                }

                return accumulated
            }

            // 短音频直接整段识别
            // FunASR Nano LLM 自带标点，不需要后处理
            return recognizer.transcribe(samples: samples) ?? ""
        }

        Self.allResults.append(PipelineResult(pipelineName: "FunASR Nano LLM", results: results))
    }

    // MARK: - 报告生成

    func testZZ_GenerateComparisonReport() throws {
        try XCTSkipIf(Self.allResults.isEmpty, "无 Pipeline 结果可汇总")

        let entries = Self.entries
        let timestamp = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.string(from: Date())
        }()

        var lines: [String] = []
        func w(_ s: String = "") { lines.append(s) }

        w("# ASR Pipeline 量化对比评估报告 (Swift)")
        w()
        w("*生成时间：\(timestamp)*")
        w("*测试集：\(entries.count) 条音频（corpus.json + real_manifest.json）*")
        w("*Pipeline：\(Self.allResults.map(\.pipelineName).joined(separator: ", "))*")
        w("*运行方式：Swift XCTest（直接复用产品代码）*")
        w()
        w("**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。")
        w()
        w("---")
        w()

        // 总体汇总
        w("## 1. 总体 CER 汇总")
        w()
        w("| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |")
        w("|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|")

        let totalAudio = entries.reduce(0.0) { $0 + $1.durationSec }

        for pr in Self.allResults {
            let rs = pr.results
            guard !rs.isEmpty else { continue }
            let avgCER = rs.map(\.cer).reduce(0, +) / Double(rs.count)
            let perfect = rs.filter { $0.cer < 0.001 }.count
            let low = rs.filter { $0.cer <= 0.10 }.count
            let mid = rs.filter { $0.cer <= 0.20 }.count
            let high = rs.filter { $0.cer > 0.20 }.count
            let totalTime = rs.map(\.elapsed).reduce(0, +)
            let rtf = totalAudio > 0 ? totalTime / totalAudio : 0

            w("| \(pr.pipelineName) | \(String(format: "%.4f", avgCER)) | \(perfect)/\(rs.count) | \(low) | \(mid) | \(high) | \(String(format: "%.1f", totalTime))s | \(String(format: "%.3f", rtf))x |")
        }

        w()
        w("---")
        w()

        // 分类汇总
        w("## 2. 按类别 CER 汇总")
        w()

        let categories = Array(Set(entries.map(\.category))).sorted()
        let pipelineNames = Self.allResults.map(\.pipelineName)

        w("| 类别 | 条数 | " + pipelineNames.joined(separator: " | ") + " |")
        w("|------|:----:|" + pipelineNames.map { _ in ":------:" }.joined(separator: "|") + "|")

        for cat in categories {
            let catEntryIds = Set(entries.filter { $0.category == cat }.map(\.id))
            let count = catEntryIds.count
            var cols = "| \(cat) | \(count) |"
            for pr in Self.allResults {
                let catResults = pr.results.filter { catEntryIds.contains($0.id) }
                if catResults.isEmpty {
                    cols += " - |"
                } else {
                    let avg = catResults.map(\.cer).reduce(0, +) / Double(catResults.count)
                    cols += " \(String(format: "%.3f", avg)) |"
                }
            }
            w(cols)
        }

        w()
        w("---")
        w()

        // 逐条详细
        w("## 3. 逐条 CER 详细")
        w()
        w("| # | ID | " + pipelineNames.joined(separator: " | ") + " | 期望文本 |")
        w("|---|-----|" + pipelineNames.map { _ in ":------:" }.joined(separator: "|") + "|------|")

        for (idx, entry) in entries.enumerated() {
            var cols = "| \(idx + 1) | \(entry.id) |"
            for pr in Self.allResults {
                if let r = pr.results.first(where: { $0.id == entry.id }) {
                    cols += " \(String(format: "%.3f", r.cer)) |"
                } else {
                    cols += " - |"
                }
            }
            let truncated = entry.expectedText.count > 30
                ? String(entry.expectedText.prefix(30)) + "..."
                : entry.expectedText
            cols += " \(truncated) |"
            w(cols)
        }

        w()

        // 错误分析（CER > 0.20 的条目详情）
        w("---")
        w()
        w("## 4. 高 CER 条目详情 (CER > 0.20)")
        w()
        for pr in Self.allResults {
            let highCER = pr.results.filter { $0.cer > 0.20 }.sorted { $0.cer > $1.cer }
            if highCER.isEmpty { continue }
            w("### \(pr.pipelineName)")
            w()
            w("| # | ID | CER | 期望文本 | 实际输出 | 分析 |")
            w("|---|-----|:---:|---------|---------|------|")
            for (i, r) in highCER.enumerated() {
                w("| \(i + 1) | \(r.id) | \(String(format: "%.3f", r.cer)) | \(r.expected) | \(r.actual) | |")
            }
            w()
        }

        let report = lines.joined(separator: "\n")
        Self.log(report)

        // 写入文件
        let projectRoot = TestEnvironment.projectRoot()
        let outputPath = projectRoot + "/docs/benchmark-report-swift.md"
        try? report.write(toFile: outputPath, atomically: true, encoding: .utf8)
        Self.log("\n[Benchmark] 报告已保存到: \(outputPath)")
    }

    // MARK: - 辅助方法

    /// 运行一个 Pipeline 对所有条目的评估
    private func runPipeline(
        name: String,
        transcribe: (BenchmarkEntry) throws -> String
    ) -> [(id: String, category: String, expected: String, actual: String, cer: Double, elapsed: Double)] {

        var results: [(id: String, category: String, expected: String, actual: String, cer: Double, elapsed: Double)] = []

        Self.log("\n[\(name)] 开始评估 \(Self.entries.count) 条...")

        for (i, entry) in Self.entries.enumerated() {
            let startTime = CFAbsoluteTimeGetCurrent()
            let output: String
            do {
                output = try transcribe(entry)
            } catch {
                Self.log("  [\(i+1)/\(Self.entries.count)] [SKIP] \(entry.id): \(error)")
                continue
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            let cer = Self.computeBenchmarkCER(actual: output, expected: entry.expectedText)
            results.append((
                id: entry.id, category: entry.category,
                expected: entry.expectedText, actual: output,
                cer: cer, elapsed: elapsed
            ))

            let tag = cer <= 0.15 ? "OK" : (cer <= 0.30 ? "WARN" : "HIGH")
            Self.log("  [\(String(format: "%3d", i+1))/\(Self.entries.count)] [\(tag)] CER=\(String(format: "%.3f", cer)) | \(entry.id)")
            if cer > 0.001 {
                Self.log("    期望: \(entry.expectedText)")
                Self.log("    实际: \(output)")
            }
        }

        let avgCER = results.isEmpty ? 0 : results.map(\.cer).reduce(0, +) / Double(results.count)
        Self.log("[\(name)] 完成。平均 CER: \(String(format: "%.4f", avgCER)) (\(results.count) 条)")

        return results
    }

    /// 后处理：CSC → 标点（Paraformer 使用）
    static func applyPostProcessing(_ text: String) -> String {
        var result = text
        if let corrector = corrector {
            result = corrector.correctSpelling(result)
        }
        if let punctuator = punctuator {
            result = punctuator.addPunctuation(text: result)
        }
        return result
    }

    /// CER 计算：保留标点，仅 lower + 去空格
    static func computeBenchmarkCER(actual: String, expected: String) -> Double {
        let normActual = normalizeBenchmark(actual)
        let normExpected = normalizeBenchmark(expected)
        return FuzzyASRMatcher.computeCER(actual: normActual, expected: normExpected)
    }

    /// Benchmark 专用标准化：仅 lower + 去空格，保留标点
    static func normalizeBenchmark(_ text: String) -> String {
        var result = text.lowercased()
        result = result.components(separatedBy: .whitespacesAndNewlines).joined()
        return result
    }
}
