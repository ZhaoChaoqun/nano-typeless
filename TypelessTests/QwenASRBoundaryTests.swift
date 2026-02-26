import XCTest
@testable import Nano_Typeless

/// QwenASR 流式识别边界情况测试
/// 这些测试需要加载真实模型，无模型时自动跳过
class QwenASRBoundaryTests: XCTestCase {

    static var recognizer: QwenASRStreamRecognizer?
    static var modelAvailable = false

    override class func setUp() {
        super.setUp()
        if let dir = TestEnvironment.qwenModelDirectory() {
            recognizer = QwenASRStreamRecognizer(modelDir: dir, numThreads: 4)
            modelAvailable = recognizer != nil
        }
    }

    override class func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.modelAvailable,
                          "Qwen3-ASR 模型不可用，跳过边界测试")
    }

    // MARK: - Chunk 边界行为

    /// 极小 chunk (10ms = 160 样本)
    func testTinyChunks_160samples() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        // 加载测试音频（使用项目中已有的或 fixtures 中的）
        let samples = try loadTestAudioOrSkip()

        // 以 160 样本（10ms）为单位推送
        let chunkSize = 160
        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            _ = recognizer.pushAudio(samples: chunk, finalize: false)
        }

        // finalize
        let silence = [Float](repeating: 0, count: 32000)
        _ = recognizer.pushAudio(samples: silence, finalize: true)

        let result = recognizer.getResult()
        print("[Boundary] Tiny chunks result: \(result)")
        // 不断言具体内容，仅断言不崩溃且有输出
        XCTAssertFalse(result.isEmpty, "极小 chunk 仍应产生识别结果")
    }

    /// 标准 chunk (1s = 16000 样本)
    func testNormalChunks_16000samples() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let samples = try loadTestAudioOrSkip()

        let chunkSize = 16000
        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            _ = recognizer.pushAudio(samples: chunk, finalize: false)
        }

        let silence = [Float](repeating: 0, count: 32000)
        _ = recognizer.pushAudio(samples: silence, finalize: true)

        let result = recognizer.getResult()
        print("[Boundary] Normal chunks result: \(result)")
        XCTAssertFalse(result.isEmpty, "标准 chunk 应产生识别结果")
    }

    /// 一次性推入所有音频
    func testSinglePushAllAtOnce() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let samples = try loadTestAudioOrSkip()
        _ = recognizer.pushAudio(samples: samples, finalize: true)

        let result = recognizer.getResult()
        print("[Boundary] Single push result: \(result)")
        XCTAssertFalse(result.isEmpty, "一次性推入应产生识别结果")
    }

    /// 交替大小 chunk，验证结果一致性
    func testVariableChunkSizes() throws {
        let recognizer = Self.recognizer!

        let samples = try loadTestAudioOrSkip()

        // 方式1：固定 chunk
        recognizer.reset()
        let chunkSize = 16000
        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            _ = recognizer.pushAudio(samples: Array(samples[i..<end]), finalize: false)
        }
        _ = recognizer.pushAudio(samples: [Float](repeating: 0, count: 32000), finalize: true)
        let result1 = recognizer.getResult()

        // 方式2：交替大小 chunk
        recognizer.reset()
        let chunkSizes = [800, 16000, 3200, 8000, 1600]
        var offset = 0
        var sizeIndex = 0
        while offset < samples.count {
            let size = chunkSizes[sizeIndex % chunkSizes.count]
            let end = min(offset + size, samples.count)
            _ = recognizer.pushAudio(samples: Array(samples[offset..<end]), finalize: false)
            offset = end
            sizeIndex += 1
        }
        _ = recognizer.pushAudio(samples: [Float](repeating: 0, count: 32000), finalize: true)
        let result2 = recognizer.getResult()

        print("[Boundary] Fixed chunks: \(result1)")
        print("[Boundary] Variable chunks: \(result2)")

        // 两种方式的结果应该相近（允许少量差异）
        let normalized1 = FuzzyASRMatcher.normalize(result1)
        let normalized2 = FuzzyASRMatcher.normalize(result2)
        if !normalized1.isEmpty && !normalized2.isEmpty {
            let cer = FuzzyASRMatcher.computeCER(actual: normalized2, expected: normalized1)
            print("[Boundary] CER between fixed/variable chunks: \(String(format: "%.3f", cer))")
            XCTAssertLessThan(cer, 0.5, "不同 chunk 大小的结果差异应在合理范围内")
        }
    }

    // MARK: - UTF-8 / 文本完整性

    /// 验证 getResult() 始终返回完整累积文本
    func testGetResultAlwaysReturnsFullText() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let samples = try loadTestAudioOrSkip()
        let chunkSize = 16000
        var lastFullText = ""

        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            _ = recognizer.pushAudio(samples: chunk, finalize: false)
            let fullText = recognizer.getResult()

            // 累积文本应该只增不减
            if !fullText.isEmpty {
                XCTAssertGreaterThanOrEqual(fullText.count, lastFullText.count,
                    "getResult() 应返回持续增长的累积文本（\(fullText.count) < \(lastFullText.count)）")
                lastFullText = fullText
            }
        }
    }

    /// 即使某次 pushAudio 返回 nil（无 delta），getResult 不应丢失内容
    func testDeltaDropDoesNotLoseText() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let samples = try loadTestAudioOrSkip()
        let chunkSize = 16000
        var nonNilDeltaCount = 0
        var previousGetResult = ""

        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            let delta = recognizer.pushAudio(samples: chunk, finalize: false)

            if delta != nil {
                nonNilDeltaCount += 1
            }

            let currentResult = recognizer.getResult()
            // getResult 不应回退
            XCTAssertGreaterThanOrEqual(currentResult.count, previousGetResult.count,
                "getResult 在 delta=\(delta == nil ? "nil" : "有值") 时不应回退")
            previousGetResult = currentResult
        }

        print("[Boundary] non-nil delta count: \(nonNilDeltaCount)")
    }

    // MARK: - 静音幻觉检测

    /// 纯静音应产生空结果
    func testPureSilenceProducesNoText() {
        let recognizer = Self.recognizer!
        recognizer.reset()

        // 3 秒纯零值
        let silence = [Float](repeating: 0, count: 48000)
        _ = recognizer.pushAudio(samples: silence, finalize: true)

        let result = recognizer.getResult()
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Boundary] Pure silence result: '\(result)'")
        XCTAssertTrue(trimmed.isEmpty,
                      "纯静音不应产生识别文本，但得到: '\(result)'")
    }

    /// 语音后的长静音不应产生幻觉
    func testTrailingSilenceNoHallucination() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let samples = try loadTestAudioOrSkip()

        // 先推入真实音频
        _ = recognizer.pushAudio(samples: samples, finalize: false)
        let textAfterSpeech = recognizer.getResult()

        // 再推入 5 秒静音
        let longSilence = [Float](repeating: 0, count: 80000)
        _ = recognizer.pushAudio(samples: longSilence, finalize: true)
        let textAfterSilence = recognizer.getResult()

        print("[Boundary] After speech: \(textAfterSpeech)")
        print("[Boundary] After silence: \(textAfterSilence)")

        // 静音后文本不应大幅增长（允许少量标点/空白差异）
        let growth = textAfterSilence.count - textAfterSpeech.count
        XCTAssertLessThan(growth, 20,
            "尾部静音后文本增长了 \(growth) 个字符，可能存在幻觉")
    }

    // MARK: - 内存增长监控

    /// 模拟 5 分钟录音，监控内存增长
    /// 注意：Qwen3-ASR 是 LLM-based，初始 KV cache 分配会占用大量内存。
    /// 此测试关注的是稳态阶段（warm-up 后）的内存增长是否合理。
    func testMemoryGrowthOver5Minutes() throws {
        let recognizer = Self.recognizer!
        recognizer.reset()

        let tracker = MemoryMonitor.Tracker()

        // 模拟 5 分钟：300 次 1 秒 chunk
        let oneSecondChunk = [Float](repeating: 0.001, count: 16000)

        // Warm-up 阶段：前 1 分钟让 LLM KV cache 完成初始分配
        for _ in 0..<60 {
            _ = recognizer.pushAudio(samples: oneSecondChunk, finalize: false)
        }
        tracker.record(label: "after warm-up (1 min)")

        // 稳态阶段：后 4 分钟测量增量内存
        for minute in 1..<5 {
            for _ in 0..<60 {
                _ = recognizer.pushAudio(samples: oneSecondChunk, finalize: false)
            }
            tracker.record(label: "after \(minute + 1) min")
        }

        // finalize
        _ = recognizer.pushAudio(samples: [Float](repeating: 0, count: 32000), finalize: true)
        tracker.record(label: "after finalize")

        tracker.printReport()

        // 稳态阶段（warm-up 后）的内存增长不应超过 200MB
        // Qwen3-ASR LLM KV cache 会随音频长度增长，但增速应可控
        XCTAssertLessThan(tracker.totalGrowthMB, 200.0,
            "稳态阶段内存增长 \(String(format: "%.1f", tracker.totalGrowthMB)) MB，超出限制")
    }

    // MARK: - Helpers

    private func loadTestAudioOrSkip() throws -> [Float] {
        let audioPath = TestEnvironment.fixturesPath() + "/audio/say/zh_short_01.wav"
        if FileManager.default.fileExists(atPath: audioPath) {
            let wav = try WAVLoader.load(path: audioPath)
            return wav.samples
        }

        throw XCTSkip("测试语音音频不可用（tests/fixtures/audio/say/zh_short_01.wav），请先运行 scripts/generate_test_corpus.py 生成测试语料")
    }
}
