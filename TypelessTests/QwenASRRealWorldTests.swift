import XCTest
@testable import Nano_Typeless

/// Qwen3-ASR 真实录音识别测试
/// 使用 AISHELL-1、MINDS-14、ASCEND、WenetSpeech 数据
/// 音频数据需先运行: uv run python scripts/download_recorded_corpus.py
class QwenASRRealWorldTests: XCTestCase {

    static var recognizer: QwenASRStreamRecognizer?
    static var corpus: Corpus?
    static var fixturesPath: String = ""
    static var modelAvailable = false
    static var audioAvailable = false

    override class func setUp() {
        super.setUp()

        guard let dir = TestEnvironment.qwenModelDirectory() else { return }
        recognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4)
        modelAvailable = recognizer != nil

        fixturesPath = TestEnvironment.fixturesPath()
        let manifestPath = fixturesPath + "/recorded_manifest.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) {
            corpus = try? JSONDecoder().decode(Corpus.self, from: data)
        }

        // Check if real audio directory exists with content
        let realAudioDir = fixturesPath + "/audio/recorded"
        audioAvailable = FileManager.default.fileExists(atPath: realAudioDir)
    }

    override class func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.modelAvailable, "Qwen3-ASR 模型不可用")
        try XCTSkipUnless(Self.audioAvailable,
            "真实录音测试音频不可用。运行: uv run python scripts/download_recorded_corpus.py")
        try XCTSkipIf(Self.corpus == nil, "recorded_manifest.json 不存在或无法解析")
    }

    // MARK: - AISHELL-1 (标准普通话基准)

    func testAishell001() throws { try runRealEntry(id: "aishell_test_001") }
    func testAishell002() throws { try runRealEntry(id: "aishell_test_002") }
    func testAishell003() throws { try runRealEntry(id: "aishell_test_003") }
    func testAishell004() throws { try runRealEntry(id: "aishell_test_004") }
    func testAishell005() throws { try runRealEntry(id: "aishell_test_005") }
    func testAishell006() throws { try runRealEntry(id: "aishell_test_006") }
    func testAishell007() throws { try runRealEntry(id: "aishell_test_007") }
    func testAishell008() throws { try runRealEntry(id: "aishell_test_008") }

    // MARK: - Conversational Mandarin (MINDS-14 真实对话录音)

    func testConversational001() throws { try runRealEntry(id: "conv_zh_001") }
    func testConversational004() throws { try runRealEntry(id: "conv_zh_004") }
    func testConversational005() throws { try runRealEntry(id: "conv_zh_005") }

    // MARK: - ASCEND Code-Switching (真实中英代码切换对话)

    func testAscendCS001() throws { try runRealEntry(id: "ascend_cs_001") }
    func testAscendCS002() throws { try runRealEntry(id: "ascend_cs_002") }
    func testAscendCS003() throws { try runRealEntry(id: "ascend_cs_003") }
    func testAscendCS004() throws { try runRealEntry(id: "ascend_cs_004") }
    func testAscendCS005() throws { try runRealEntry(id: "ascend_cs_005") }
    func testAscendCS006() throws { try runRealEntry(id: "ascend_cs_006") }
    func testAscendCS008() throws { try runRealEntry(id: "ascend_cs_008") }
    func testAscendCS009() throws { try runRealEntry(id: "ascend_cs_009") }
    func testAscendCS010() throws { try runRealEntry(id: "ascend_cs_010") }

    // MARK: - WenetSpeech TEST_NET (多场景中文)

    func testWenetNet001() throws { try runRealEntry(id: "wenet_net_001") }
    func testWenetNet002() throws { try runRealEntry(id: "wenet_net_002") }
    func testWenetNet003() throws { try runRealEntry(id: "wenet_net_003") }
    func testWenetNet004() throws { try runRealEntry(id: "wenet_net_004") }
    func testWenetNet005() throws { try runRealEntry(id: "wenet_net_005") }
    func testWenetNet006() throws { try runRealEntry(id: "wenet_net_006") }
    func testWenetNet007() throws { try runRealEntry(id: "wenet_net_007") }
    func testWenetNet008() throws { try runRealEntry(id: "wenet_net_008") }
    func testWenetNet009() throws { try runRealEntry(id: "wenet_net_009") }
    func testWenetNet010() throws { try runRealEntry(id: "wenet_net_010") }

    // MARK: - Aggregate CER Report

    func testAggregateCERReport() throws {
        guard let entries = Self.corpus?.entries else {
            throw XCTSkip("recorded_manifest.json 中无条目")
        }

        var results: [(id: String, cer: Double)] = []

        for entry in entries {
            guard entry.matchMode == "character_error_rate" else { continue }
            guard let samples = try? loadRealAudio(entry) else { continue }

            let recognizer = Self.recognizer!
            recognizer.reset()
            _ = recognizer.pushAudio(samples: samples, finalize: true)
            let result = recognizer.getResult()

            let cer = FuzzyASRMatcher.computeMinCER(actual: result, expectedTexts: entry.expectedTexts)
            results.append((id: entry.id, cer: cer))
        }

        guard !results.isEmpty else {
            throw XCTSkip("无 CER 模式的测试条目可用")
        }

        // Print report
        print("\n[Real-World CER Report]")
        for r in results {
            let status = r.cer <= 0.20 ? "✓" : "✗"
            print("  \(status) \(r.id): CER = \(String(format: "%.3f", r.cer))")
        }
        let avgCER = results.map(\.cer).reduce(0, +) / Double(results.count)
        print("  Average CER: \(String(format: "%.3f", avgCER))")
        print("  Samples: \(results.count)")

        XCTAssertLessThan(avgCER, 0.20,
            "真实世界数据平均 CER (\(String(format: "%.3f", avgCER))) 应 < 0.20")
    }

    // MARK: - Core Helpers

    private func runRealEntry(id: String) throws {
        guard let entry = Self.corpus?.entries.first(where: { $0.id == id }) else {
            throw XCTSkip("条目 '\(id)' 在 recorded_manifest.json 中不存在")
        }

        let samples = try loadRealAudio(entry)

        let recognizer = Self.recognizer!
        recognizer.reset()

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = recognizer.pushAudio(samples: samples, finalize: true)
        let result = recognizer.getResult()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Logging
        print("[Real] \(id)")
        print("  Expected: \(entry.expectedTexts.first ?? "")")
        print("  Actual:   \(result)")
        print("  Elapsed:  \(String(format: "%.2f", elapsed))s")

        // Match via FuzzyASRMatcher
        let mode = FuzzyASRMatcher.matchMode(for: entry)
        let passed = FuzzyASRMatcher.matches(
            actual: result, expectedTexts: entry.expectedTexts, mode: mode)

        if !passed {
            let cer = FuzzyASRMatcher.computeMinCER(actual: result, expectedTexts: entry.expectedTexts)
            print("  CER: \(String(format: "%.3f", cer))")
        }

        XCTAssertTrue(passed,
            "[\(id)] 识别不匹配。期望: '\(entry.expectedTexts.first ?? "")', 实际: '\(result)'")
    }

    private func loadRealAudio(_ entry: CorpusEntry) throws -> [Float] {
        let preference = ["recorded"]

        for source in preference {
            if let relPath = entry.audioFiles[source] {
                let fullPath = Self.fixturesPath + "/" + relPath
                if FileManager.default.fileExists(atPath: fullPath) {
                    let wav = try WAVLoader.load(path: fullPath)
                    return wav.samples
                }
            }
        }

        throw XCTSkip("'\(entry.id)' 的音频文件不可用。"
            + "运行: uv run python scripts/download_recorded_corpus.py")
    }
}
