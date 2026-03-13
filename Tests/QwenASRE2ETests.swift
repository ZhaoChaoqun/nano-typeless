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

        // 查找模型目录
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models/Qwen3-ASR-0.6B")
        let modelDir: String? = {
            if FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("vocab.json").path) {
                return appSupport.path
            }
            if let envDir = ProcessInfo.processInfo.environment["QWEN_MODEL_DIR"],
               FileManager.default.fileExists(atPath: envDir + "/vocab.json") {
                return envDir
            }
            return nil
        }()

        guard let dir = modelDir else { return }
        recognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4)
        modelAvailable = recognizer != nil

        // 查找 fixtures 目录
        fixturesPath = findProjectRoot() + "/tests/fixtures"
        let corpusPath = fixturesPath + "/synthetic_manifest.json"
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
        try XCTSkipIf(Self.corpus == nil, "synthetic_manifest.json 不可用，请先运行 generate_synthetic_corpus.py")
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
        let passed = FuzzyASRMatcher.matches(actual: result, expectedTexts: entry.expectedTexts, mode: mode)
        XCTAssertTrue(passed,
            "流式识别不匹配。期望: '\(entry.expectedTexts.first ?? "")', 实际: '\(result)'")
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
        print("  Expected: \(entry.expectedTexts.first ?? "")")
        print("  Actual:   \(result)")
        print("  Elapsed:  \(String(format: "%.2f", elapsed))s")
        print("  Memory:   \(String(format: "%.1f", memBefore)) → \(String(format: "%.1f", memAfter)) MB")

        // 匹配断言
        let mode = FuzzyASRMatcher.matchMode(for: entry)
        let passed = FuzzyASRMatcher.matches(actual: result, expectedTexts: entry.expectedTexts, mode: mode)

        if !passed {
            // 额外输出 CER 辅助调试
            let cer = FuzzyASRMatcher.computeMinCER(actual: result, expectedTexts: entry.expectedTexts)
            print("  CER: \(String(format: "%.3f", cer))")
        }

        XCTAssertTrue(passed,
            "[\(id)] 识别不匹配。期望: '\(entry.expectedTexts.first ?? "")', 实际: '\(result)'")
    }

    private func findEntry(id: String) throws -> CorpusEntry {
        guard let entry = Self.corpus?.entries.first(where: { $0.id == id }) else {
            throw XCTSkip("语料条目 '\(id)' 在 synthetic_manifest.json 中不存在")
        }
        return entry
    }

    private func loadAudioForEntry(_ entry: CorpusEntry) throws -> [Float] {
        // 优先 synthetic
        let preference = ["synthetic"]

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

    private static func findProjectRoot() -> String {
        // 从当前文件路径推断，或使用环境变量
        if let root = ProcessInfo.processInfo.environment["PROJECT_ROOT"] {
            return root
        }

        // 尝试从 Bundle 推断
        var path = Bundle.main.bundlePath
        while !path.isEmpty && path != "/" {
            if FileManager.default.fileExists(atPath: path + "/Package.swift") {
                return path
            }
            path = (path as NSString).deletingLastPathComponent
        }

        return FileManager.default.currentDirectoryPath
    }
}
