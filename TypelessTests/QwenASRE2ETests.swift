import XCTest
@testable import Nano_Typeless

/// QwenASR 端到端集成测试
/// 加载真实模型，使用 Phase 1 生成的语料进行完整的识别测试
class QwenASRE2ETests: XCTestCase {

    static var recognizer: QwenASRStreamRecognizer?
    static var corpus: Corpus?
    static var fixturesPath: String = ""
    static var modelAvailable = false

    override class func setUp() {
        super.setUp()

        guard let dir = TestEnvironment.qwenModelDirectory() else { return }
        recognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4)
        modelAvailable = recognizer != nil

        fixturesPath = TestEnvironment.fixturesPath()
        let corpusPath = fixturesPath + "/corpus.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: corpusPath)) {
            corpus = try? JSONDecoder().decode(Corpus.self, from: data)
        }
    }

    override class func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.modelAvailable, "Qwen3-ASR 模型不可用")
        try XCTSkipIf(Self.corpus == nil, "corpus.json 不可用，请先运行 generate_test_corpus.py")
    }

    // MARK: - 逐条语料测试

    func testChineseShort() throws {
        try runCorpusEntry(id: "zh_short_01")
    }

    func testChineseLong() throws {
        try runCorpusEntry(id: "zh_long_01")
    }

    func testMixedZhEn() throws {
        try runCorpusEntry(id: "mixed_01")
    }

    func testMixedTechnical() throws {
        try runCorpusEntry(id: "mixed_02")
    }

    func testEnglishShort() throws {
        try runCorpusEntry(id: "en_short_01")
    }

    func testTechnicalNumbers() throws {
        try runCorpusEntry(id: "tech_num_01")
    }

    func testSilence() throws {
        try runCorpusEntry(id: "silence_01")
    }

    func testShortSilence() throws {
        try runCorpusEntry(id: "silence_02")
    }

    func testSpeechWithTrailingSilence() throws {
        try runCorpusEntry(id: "noise_01")
    }

    // MARK: - 开发者术语 (Developer Corpus)

    func testDevGitCommand() throws {
        try runCorpusEntry(id: "dev_git_01")
    }

    func testDevSwiftStruct() throws {
        try runCorpusEntry(id: "dev_swift_01")
    }

    func testDevRustAsync() throws {
        try runCorpusEntry(id: "dev_rust_01")
    }

    func testDevKubernetes() throws {
        try runCorpusEntry(id: "dev_k8s_01")
    }

    func testDevRESTfulAPI() throws {
        try runCorpusEntry(id: "dev_api_01")
    }

    func testDevSQLQuery() throws {
        try runCorpusEntry(id: "dev_db_01")
    }

    func testDevURL() throws {
        try runCorpusEntry(id: "dev_url_01")
    }

    func testDevBreakpoint() throws {
        try runCorpusEntry(id: "dev_debug_01")
    }

    // MARK: - Code-Switching 中英句内混合

    func testCodeSwitchVariable() throws {
        try runCorpusEntry(id: "cs_var_01")
    }

    func testCodeSwitchBuild() throws {
        try runCorpusEntry(id: "cs_build_01")
    }

    func testCodeSwitchError() throws {
        try runCorpusEntry(id: "cs_error_01")
    }

    func testCodeSwitchDeploy() throws {
        try runCorpusEntry(id: "cs_deploy_01")
    }

    func testCodeSwitchReview() throws {
        try runCorpusEntry(id: "cs_review_01")
    }

    // MARK: - 幻觉压力测试 (Hallucination)

    func testHallucination10sSilence() throws {
        try runCorpusEntry(id: "hal_silence_10s")
    }

    func testHallucination30sSilence() throws {
        try runCorpusEntry(id: "hal_silence_30s")
    }

    func testHallucinationWhiteNoise() throws {
        try runCorpusEntry(id: "hal_white_noise_01")
    }

    func testHallucinationBreathing() throws {
        try runCorpusEntry(id: "hal_breath_01")
    }

    // MARK: - 标点 & 格式 (Punctuation)

    func testPunctuationQuestion() throws {
        try runCorpusEntry(id: "punct_question_01")
    }

    func testPunctuationExclamation() throws {
        try runCorpusEntry(id: "punct_exclaim_01")
    }

    func testPunctuationList() throws {
        try runCorpusEntry(id: "punct_list_01")
    }

    // MARK: - 语速变化 (Speech Rate)

    func testFastSpeech() throws {
        try runCorpusEntry(id: "rate_fast_01")
    }

    func testSlowSpeech() throws {
        try runCorpusEntry(id: "rate_slow_01")
    }

    // MARK: - 长音频 (Long Audio)

    func testLongAudio30s() throws {
        try runCorpusEntry(id: "long_30s_01")
    }

    func testLongAudio60s() throws {
        try runCorpusEntry(id: "long_60s_01")
    }

    // MARK: - 中途停顿 (Mid-sentence Pause)

    func testMidSentencePause() throws {
        try runCorpusEntry(id: "pause_mid_01")
    }

    func testLongHesitation() throws {
        try runCorpusEntry(id: "pause_long_01")
    }

    // MARK: - 流式模拟测试

    /// 以 0.5 秒 chunk 模拟真实流式识别
    func testStreamingSimulation() throws {
        let entry = try findEntry(id: "zh_short_01")
        let samples = try loadAudioForEntry(entry)
        let recognizer = Self.recognizer!
        recognizer.reset()

        let chunkSize = 8000  // 0.5 秒
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            _ = recognizer.pushAudio(samples: chunk, finalize: false)
        }

        // 2 秒静音 padding + finalize
        let silence = [Float](repeating: 0, count: 32000)
        _ = recognizer.pushAudio(samples: silence, finalize: true)

        let result = recognizer.getResult()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        print("[E2E-Stream] Result: \(result)")
        print("[E2E-Stream] Elapsed: \(String(format: "%.2f", elapsed))s")
        print("[E2E-Stream] Memory: \(String(format: "%.1f", MemoryMonitor.currentRSSInMB())) MB")

        XCTAssertFalse(result.isEmpty, "流式识别应有输出")

        let mode = FuzzyASRMatcher.matchMode(for: entry)
        let passed = FuzzyASRMatcher.matches(actual: result, expected: entry.expectedText, mode: mode)
        XCTAssertTrue(passed,
            "流式识别不匹配。期望: '\(entry.expectedText)', 实际: '\(result)'")
    }

    // MARK: - UTF-8 边界条件压力测试 (Regression: Split UTF-8 BPE Tokens)

    /// 用极小 chunk (20ms = 320 samples) 送入中文音频，验证输出不含 U+FFFD。
    ///
    /// 此测试专门防止 GPT-2 byte-level BPE token 在跨 UTF-8 字节边界拆分时
    /// 产生 mojibake (U+FFFD)。极小 chunk 最大化了 chunk 边界恰好切到多字节
    /// 字符中间的概率。
    func testStreamingWithTinyChunks_AvoidsMojibake() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        // 使用 edge_tts 中文音频
        let entry = try findEntry(id: "zh_short_01")
        let samples = try loadAudioForEntry(entry)

        // 极小 chunk: 20ms = 320 samples at 16kHz
        let chunkSize = 320
        var deltaTexts: [String] = []

        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            if let delta = recognizer.pushAudio(samples: chunk, finalize: false) {
                deltaTexts.append(delta)
            }
        }

        // finalize
        let silence = [Float](repeating: 0, count: 32000)
        if let delta = recognizer.pushAudio(samples: silence, finalize: true) {
            deltaTexts.append(delta)
        }

        let result = recognizer.getResult()

        print("[UTF8-Tiny] Final result: \(result)")
        print("[UTF8-Tiny] Delta count: \(deltaTexts.count)")

        // 核心断言：输出不含 U+FFFD (Replacement Character)
        XCTAssertFalse(result.contains("\u{FFFD}"),
            "输出包含 U+FFFD 替换字符，说明存在 UTF-8 边界损坏: '\(result)'")

        // Delta 也不应包含 U+FFFD
        for (i, delta) in deltaTexts.enumerated() {
            XCTAssertFalse(delta.contains("\u{FFFD}"),
                "Delta #\(i) 包含 U+FFFD: '\(delta)'")
        }

        // 应有输出
        XCTAssertFalse(result.isEmpty, "极小 chunk 流式识别应有输出")
    }

    /// 用 1024 样本 (64ms) chunk 送入多条中文音频，交叉验证 mojibake。
    func testStreamingSmallChunks_MultipleAudio_NoMojibake() throws {
        let recognizer = Self.recognizer!
        let chunkSize = 1024  // 64ms

        // 测试多条中文相关语料
        let testIDs = ["zh_short_01", "mixed_01", "mixed_02"]
        var testedCount = 0

        for id in testIDs {
            guard let entry = Self.corpus?.entries.first(where: { $0.id == id }) else {
                continue
            }
            guard let samples = try? loadAudioForEntry(entry) else {
                continue
            }

            recognizer.reset()

            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                _ = recognizer.pushAudio(samples: chunk, finalize: false)
            }

            let silence = [Float](repeating: 0, count: 32000)
            _ = recognizer.pushAudio(samples: silence, finalize: true)

            let result = recognizer.getResult()

            print("[UTF8-Small] \(id): \(result)")

            XCTAssertFalse(result.contains("\u{FFFD}"),
                "[\(id)] 输出包含 U+FFFD: '\(result)'")

            testedCount += 1
        }

        XCTAssertGreaterThan(testedCount, 0, "至少应测试一条语料")
    }

    /// 用 AISHELL 真实录音 + 超小 chunk 测试，验证真实口语不会触发 mojibake。
    func testStreamingRealAudio_TinyChunks_NoMojibake() throws {
        let recognizer = Self.recognizer!
        let chunkSize = 640  // 40ms

        let audioDir = Self.fixturesPath + "/audio/real/aishell"
        let fm = FileManager.default
        guard fm.fileExists(atPath: audioDir) else {
            throw XCTSkip("AISHELL 测试音频目录不存在")
        }

        let wavFiles = (try? fm.contentsOfDirectory(atPath: audioDir))?
            .filter { $0.hasSuffix(".wav") }
            .sorted()
            .prefix(3) ?? []  // 只测前 3 个避免测试太长

        guard !wavFiles.isEmpty else {
            throw XCTSkip("AISHELL 目录下无 WAV 文件")
        }

        for wavFile in wavFiles {
            let path = audioDir + "/" + wavFile
            let wav = try WAVLoader.load(path: path)
            let samples = wav.samples

            recognizer.reset()

            for i in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(i + chunkSize, samples.count)
                let chunk = Array(samples[i..<end])
                _ = recognizer.pushAudio(samples: chunk, finalize: false)
            }

            let silence = [Float](repeating: 0, count: 32000)
            _ = recognizer.pushAudio(samples: silence, finalize: true)

            let result = recognizer.getResult()

            print("[UTF8-AISHELL] \(wavFile): \(result)")

            XCTAssertFalse(result.contains("\u{FFFD}"),
                "[\(wavFile)] 输出包含 U+FFFD 替换字符: '\(result)'")
        }
    }

    /// 验证 delta (增量文本) 和 getResult (累积文本) 的一致性且均无 mojibake。
    func testStreamingDeltaConsistency_NoMojibake() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let entry = try findEntry(id: "zh_short_01")
        let samples = try loadAudioForEntry(entry)

        let chunkSize = 640  // 40ms
        var accumulatedDelta = ""

        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            if let delta = recognizer.pushAudio(samples: chunk, finalize: false) {
                accumulatedDelta += delta

                // 每个 delta 不应含 U+FFFD
                XCTAssertFalse(delta.contains("\u{FFFD}"),
                    "Delta 包含 U+FFFD 在 offset \(i): '\(delta)'")
            }
        }

        let silence = [Float](repeating: 0, count: 32000)
        if let delta = recognizer.pushAudio(samples: silence, finalize: true) {
            accumulatedDelta += delta
        }

        let fullResult = recognizer.getResult()

        print("[UTF8-Delta] Accumulated delta: \(accumulatedDelta)")
        print("[UTF8-Delta] Full result:       \(fullResult)")

        // 最终结果不含 U+FFFD
        XCTAssertFalse(fullResult.contains("\u{FFFD}"),
            "最终结果包含 U+FFFD: '\(fullResult)'")

        // Delta 拼接结果应与 getResult 一致
        XCTAssertEqual(accumulatedDelta, fullResult,
            "Delta 拼接与 getResult 不一致")
    }

    // MARK: - 性能基准

    func testPerformanceBaseline() throws {
        let entry = try findEntry(id: "zh_short_01")
        let samples = try loadAudioForEntry(entry)

        measure {
            Self.recognizer!.reset()
            _ = Self.recognizer!.pushAudio(samples: samples, finalize: true)
            _ = Self.recognizer!.getResult()
        }
    }

    // MARK: - Core Helpers

    private func runCorpusEntry(id: String) throws {
        let entry = try findEntry(id: id)
        let samples = try loadAudioForEntry(entry)

        let recognizer = Self.recognizer!
        recognizer.reset()

        let startTime = CFAbsoluteTimeGetCurrent()
        let memBefore = MemoryMonitor.currentRSSInMB()

        // 一次性推入 + finalize
        _ = recognizer.pushAudio(samples: samples, finalize: true)
        let result = recognizer.getResult()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let memAfter = MemoryMonitor.currentRSSInMB()

        // 输出详情
        print("[E2E] \(id)")
        print("  Expected: \(entry.expectedText)")
        print("  Actual:   \(result)")
        print("  Elapsed:  \(String(format: "%.2f", elapsed))s")
        print("  Memory:   \(String(format: "%.1f", memBefore)) → \(String(format: "%.1f", memAfter)) MB")

        // 匹配断言
        let mode = FuzzyASRMatcher.matchMode(for: entry)
        let passed = FuzzyASRMatcher.matches(actual: result, expected: entry.expectedText, mode: mode)

        if !passed {
            // 额外输出 CER 辅助调试
            let normalizedActual = FuzzyASRMatcher.normalize(result)
            let normalizedExpected = FuzzyASRMatcher.normalize(entry.expectedText)
            let cer = FuzzyASRMatcher.computeCER(actual: normalizedActual, expected: normalizedExpected)
            print("  CER: \(String(format: "%.3f", cer))")
        }

        XCTAssertTrue(passed,
            "[\(id)] 识别不匹配。期望: '\(entry.expectedText)', 实际: '\(result)'")
    }

    private func findEntry(id: String) throws -> CorpusEntry {
        guard let entry = Self.corpus?.entries.first(where: { $0.id == id }) else {
            throw XCTSkip("语料条目 '\(id)' 在 corpus.json 中不存在")
        }
        return entry
    }

    private func loadAudioForEntry(_ entry: CorpusEntry) throws -> [Float] {
        // 优先 edge_tts > say > synthetic
        let preference = ["edge_tts", "say", "synthetic"]

        for source in preference {
            if let relPath = entry.audioFiles[source] {
                let fullPath = Self.fixturesPath + "/" + relPath
                if FileManager.default.fileExists(atPath: fullPath) {
                    let wav = try WAVLoader.load(path: fullPath)
                    return wav.samples
                }
            }
        }

        // 静音条目：直接生成
        if entry.matchMode == "empty_or_whitespace" {
            let sampleCount = Int(entry.durationSec * 16000)
            return [Float](repeating: 0, count: max(sampleCount, 1600))
        }

        throw XCTSkip("无法加载 '\(entry.id)' 的音频文件")
    }

}
