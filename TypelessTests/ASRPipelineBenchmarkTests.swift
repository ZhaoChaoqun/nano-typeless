import XCTest
@testable import Nano_Typeless

/// ASR Pipeline Benchmark — 直接使用产品 Swift 代码评估 Pipeline
///
/// Pipeline:
///   1. Qwen3-ASR (离线): pushAudio(finalize:true) 一次性识别
///   2. Qwen3-ASR (流式): chunk+rollback 模拟流式
///   3. Paraformer Pipeline: Streaming Paraformer + ITN → CSC → CT-Transformer 标点
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
    static var punctuator: SherpaOnnxPunctuation?
    static var corrector: ChineseSpellingCorrector?
    static var cloudRewriteService: CloudRewriteService?
    static var termNormalizer: TermNormalizer?
    static var itn: SherpaOnnxITN?

    // 可用性标记
    static var qwenAvailable = false
    static var paraformerAvailable = false
    static var cloudRewriteAvailable = false

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

        // Cloud Rewrite (Azure OpenAI gpt-5.4-mini)
        cloudRewriteService = CloudRewriteService()
        cloudRewriteAvailable = (ProcessInfo.processInfo.environment["AZURE_OPENAI_API_KEY"]
            ?? GeneratedSecrets.azureOpenAIAPIKey) != nil
        log("[Benchmark] Cloud Rewrite: \(cloudRewriteAvailable ? "✓" : "✗") (Azure OpenAI)")

        // TermNormalizer
        let bundleURL = Bundle(for: ASRPipelineBenchmarkTests.self).url(forResource: "term_dictionary", withExtension: "json")
        let dictURL = bundleURL ?? URL(fileURLWithPath: TestEnvironment.projectRoot() + "/Sources/term_dictionary.json")
        termNormalizer = TermNormalizer(dictionaryURL: dictURL)
        log("[Benchmark] TermNormalizer: \(termNormalizer != nil ? "✓" : "✗")")

        // 独立 ITN（Qwen3-ASR 使用）
        if let itnFstPath = TestEnvironment.itnFstPath() {
            itn = SherpaOnnxITN(ruleFsts: itnFstPath)
            log("[Benchmark] ITN (standalone): \(itn != nil ? "✓" : "✗")")
        } else {
            log("[Benchmark] ITN (standalone): ✗ (FST 未下载)")
        }
    }

    override class func tearDown() {
        log("[Benchmark] 完成。日志已保存到: \(logPath)")
        logHandle?.closeFile()
        logHandle = nil
        qwenRecognizer = nil
        paraformerRecognizer = nil
        punctuator = nil
        corrector = nil
        cloudRewriteService = nil
        termNormalizer = nil
        itn = nil
        super.tearDown()
    }

    // MARK: - Pipeline Tests

    func testQwenASROfflinePipeline() throws {
        try XCTSkipUnless(Self.qwenAvailable, "Qwen3-ASR 模型不可用")
        let recognizer = Self.qwenRecognizer!

        let results = runPipeline(name: "Qwen3-ASR (离线)") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples
            var text = recognizer.transcribeOffline(samples: samples)
            text = Self.applyQwenPostProcessing(text)
            return text
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
            // 极少量 silence（0.1s）+ finalize：commit rollback tokens + 处理尾部音频
            // 不用 1s silence——长音频上 decoder 会 hallucinate 重复文本
            let minimalSilence = [Float](repeating: 0.0, count: 1600)
            _ = recognizer.pushAudio(samples: minimalSilence, finalize: true)
            var text = recognizer.getResult()
            text = Self.applyQwenPostProcessing(text)
            return text
        }

        Self.allResults.append(PipelineResult(pipelineName: "Qwen3-ASR (流式)", results: results))
    }

    func testParaformerPipeline() throws {
        try XCTSkipUnless(Self.paraformerAvailable, "Paraformer 模型不可用")
        let recognizer = Self.paraformerRecognizer!

        let results = runPipeline(name: "Paraformer Pipeline") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples

            // 流式推理 + is_final tail flush
            recognizer.reset()
            let chunkSize = 4096
            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                recognizer.acceptWaveform(samples: chunk)
                while recognizer.isReady() { recognizer.decode() }
            }
            recognizer.setFinalChunk()
            recognizer.inputFinished()
            while recognizer.isReady() { recognizer.decode() }
            var text = recognizer.getResult()
            recognizer.reset()

            // 后处理：CSC → 标点
            text = Self.applyPostProcessing(text)
            return text
        }

        Self.allResults.append(PipelineResult(pipelineName: "Paraformer Pipeline", results: results))
    }

    func testParaformerCloudRewritePipeline() throws {
        try XCTSkipUnless(Self.paraformerAvailable, "Paraformer 模型不可用")
        try XCTSkipUnless(Self.cloudRewriteAvailable, "Cloud Rewrite 不可用 (需要 AZURE_OPENAI_API_KEY)")
        let recognizer = Self.paraformerRecognizer!
        let rewriteService = Self.cloudRewriteService!

        let results = runPipeline(name: "Paraformer + Cloud Rewrite") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples

            // 流式推理 + is_final tail flush
            recognizer.reset()
            let chunkSize = 4096
            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                recognizer.acceptWaveform(samples: chunk)
                while recognizer.isReady() { recognizer.decode() }
            }
            recognizer.setFinalChunk()
            recognizer.inputFinished()
            while recognizer.isReady() { recognizer.decode() }
            let asrText = recognizer.getResult()
            recognizer.reset()

            // Cloud Rewrite 后处理（同步等待 async 调用）
            let semaphore = DispatchSemaphore(value: 0)
            var rewritten = asrText
            Task {
                rewritten = await rewriteService.rewriteOrPassthrough(asrText)
                semaphore.signal()
            }
            semaphore.wait()
            return rewritten
        }

        Self.allResults.append(PipelineResult(pipelineName: "Paraformer + Cloud Rewrite", results: results))
    }

    func testParaformerTermNormalizerPipeline() throws {
        try XCTSkipUnless(Self.paraformerAvailable, "Paraformer 模型不可用")
        let recognizer = Self.paraformerRecognizer!
        guard let normalizer = Self.termNormalizer else {
            throw XCTSkip("TermNormalizer 不可用")
        }

        let results = runPipeline(name: "Paraformer + TermNormalizer") { entry in
            let samples = try WAVLoader.load(path: entry.audioPath).samples

            // 流式推理 + is_final tail flush
            recognizer.reset()
            let chunkSize = 4096
            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                recognizer.acceptWaveform(samples: chunk)
                while recognizer.isReady() { recognizer.decode() }
            }
            recognizer.setFinalChunk()
            recognizer.inputFinished()
            while recognizer.isReady() { recognizer.decode() }
            var text = recognizer.getResult()
            recognizer.reset()

            // TermNormalizer → CSC → 标点
            text = normalizer.normalize(text)
            text = Self.applyPostProcessing(text)
            return text
        }

        Self.allResults.append(PipelineResult(pipelineName: "Paraformer + TermNormalizer", results: results))
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
        w("*测试集：\(entries.count) 条音频（synthetic_manifest.json + recorded_manifest.json）*")
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
            let displayExpected = entry.expectedTexts.first ?? ""
            let truncated = displayExpected.count > 30
                ? String(displayExpected.prefix(30)) + "..."
                : displayExpected
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

        // 写出 JSON 结果文件
        TestResultCollector.shared.writeJSON(suite: "benchmark")
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

            let cer = Self.computeBenchmarkMinCER(actual: output, expectedTexts: entry.expectedTexts)
            results.append((
                id: entry.id, category: entry.category,
                expected: entry.expectedTexts.first ?? "", actual: output,
                cer: cer, elapsed: elapsed
            ))

            // 收集结果到 JSON
            TestResultCollector.shared.record(
                pipelineName: name,
                entry: TestResultEntry(
                    id: entry.id, category: entry.category, language: entry.language,
                    expectedText: entry.expectedTexts.first ?? "",
                    actualText: output, cer: cer, passed: cer <= 0.10,
                    matchMode: "character_error_rate",
                    elapsedSec: elapsed,
                    audioDurationSec: entry.durationSec,
                    rtf: entry.durationSec > 0 ? elapsed / entry.durationSec : 0,
                    memoryBeforeMB: nil, memoryAfterMB: nil
                )
            )

            let tag = cer <= 0.15 ? "OK" : (cer <= 0.30 ? "WARN" : "HIGH")
            Self.log("  [\(String(format: "%3d", i+1))/\(Self.entries.count)] [\(tag)] CER=\(String(format: "%.3f", cer)) | \(entry.id)")
            if cer > 0.001 {
                Self.log("    期望: \(entry.expectedTexts.first ?? "")")
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

    /// 后处理：TermNormalizer → ITN（Qwen3-ASR 使用）
    static func applyQwenPostProcessing(_ text: String) -> String {
        var result = text
        if let normalizer = termNormalizer {
            result = normalizer.normalize(result)
        }
        if let itn = itn {
            result = itn.normalize(text: result)
        }
        return result
    }

    /// CER 计算：保留标点，仅 lower + 去空格
    static func computeBenchmarkCER(actual: String, expected: String) -> Double {
        let normActual = normalizeBenchmark(actual)
        let normExpected = normalizeBenchmark(expected)
        return FuzzyASRMatcher.computeCER(actual: normActual, expected: normExpected)
    }

    /// 多候选 CER 计算：取所有候选中的最小 CER
    static func computeBenchmarkMinCER(actual: String, expectedTexts: [String]) -> Double {
        guard !expectedTexts.isEmpty else { return 1.0 }
        return expectedTexts.map { computeBenchmarkCER(actual: actual, expected: $0) }.min() ?? 1.0
    }

    /// Benchmark 专用标准化：仅 lower + 去空格，保留标点
    static func normalizeBenchmark(_ text: String) -> String {
        var result = text.lowercased()
        result = result.components(separatedBy: .whitespacesAndNewlines).joined()
        return result
    }
}
