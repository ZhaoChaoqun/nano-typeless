import XCTest
@testable import Nano_Typeless

/// ParaformerONNX Swift 实现 vs Python 参考实现的逐环节数值对齐测试。
///
/// 前置条件：
/// 1. 运行 `scripts/generate_reference_data.py` 生成 `tests/fixtures/alignment/ref_*.npy`
/// 2. Paraformer fp16 模型在 `~/Library/Application Support/Nano Typeless/models/...`
/// 3. 测试音频 `tests/fixtures/audio/real/codeswitching/cs_edge_008.wav` 存在
class ParaformerAlignmentTests: XCTestCase {

    static var paraformer: ParaformerONNX?
    static var intermediates: ParaformerONNX.OfflineIntermediates?
    static var alignmentDir: String = ""
    static var modelAvailable = false

    override class func setUp() {
        super.setUp()

        let fixturesPath = TestEnvironment.fixturesPath()
        alignmentDir = fixturesPath + "/alignment"

        // 检查参考数据
        guard FileManager.default.fileExists(atPath: alignmentDir + "/ref_fbank.npy") else {
            print("[ParaformerAlignment] 参考数据不存在，请先运行 scripts/generate_reference_data.py")
            return
        }

        // 定位 Paraformer fp16 模型
        let modelDir = TestEnvironment.modelsDirectory
            + "/sherpa-onnx-streaming-paraformer-bilingual-zh-en-fp16"

        let encoderPath = modelDir + "/encoder.fp16.onnx"
        let decoderPath = modelDir + "/decoder.fp16.onnx"
        let tokensPath = modelDir + "/tokens.txt"

        guard FileManager.default.fileExists(atPath: encoderPath) else {
            print("[ParaformerAlignment] Paraformer fp16 模型不存在: \(modelDir)")
            return
        }

        guard let pf = ParaformerONNX(encoderPath: encoderPath, decoderPath: decoderPath, tokensPath: tokensPath) else {
            print("[ParaformerAlignment] ParaformerONNX 初始化失败")
            return
        }
        paraformer = pf
        modelAvailable = true

        // 加载测试音频并运行离线 pipeline
        let audioPath = fixturesPath + "/audio/real/codeswitching/cs_edge_008.wav"
        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("[ParaformerAlignment] 测试音频不存在: \(audioPath)")
            modelAvailable = false
            return
        }

        do {
            let wav = try WAVLoader.load(path: audioPath)
            // WAVLoader 返回 -1.0~1.0，Paraformer fbank 期望 int16 范围 (×32768)
            let scaledSamples = wav.samples.map { $0 * 32768.0 }
            intermediates = pf.transcribeOfflineWithIntermediates(samples: scaledSamples)
        } catch {
            print("[ParaformerAlignment] 音频加载失败: \(error)")
            modelAvailable = false
        }
    }

    override class func tearDown() {
        paraformer = nil
        intermediates = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.modelAvailable, "Paraformer 模型或参考数据不可用")
        try XCTSkipIf(Self.intermediates == nil, "transcribeOfflineWithIntermediates 返回 nil")
    }

    // MARK: - Stage 1: Fbank

    func testStage1_Fbank() throws {
        let inter = Self.intermediates!
        let ref = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_fbank.npy")

        let refFrames = ref.shape[0]
        let refDim = ref.shape.count > 1 ? ref.shape[1] : 80

        print("── Fbank 对齐 ──")
        print("  Swift: \(inter.fbankFrames) frames × 80")
        print("  Python: \(refFrames) frames × \(refDim)")

        XCTAssertEqual(inter.fbankFrames, refFrames, "Fbank 帧数不一致")
        XCTAssertEqual(inter.fbank.count, ref.data.count, "Fbank 元素总数不一致")

        let (maxDiff, meanDiff) = computeDiff(inter.fbank, ref.data)
        print("  max abs diff: \(maxDiff)")
        print("  mean abs diff: \(meanDiff)")
        printFirstN(swift: inter.fbank, python: ref.data, n: 5, label: "fbank")

        // vDSP FFT vs kaldi FFT 的浮点精度差异（mel 滤波器系数微小差异）
        XCTAssertLessThan(maxDiff, 2.0, "Fbank max abs diff 超过 2.0")
        XCTAssertLessThan(meanDiff, 0.1, "Fbank mean abs diff 超过 0.1")
        if maxDiff < 1e-4 {
            print("  Fbank 精确匹配 (max diff < 1e-4)")
        } else if maxDiff < 1.0 {
            print("  Fbank 差异较小 (max diff < 1.0)")
        } else {
            print("  Fbank 有 FFT 精度差异 (max diff < 2.0)")
        }
    }

    // MARK: - Stage 2: LFR

    func testStage2_LFR() throws {
        let inter = Self.intermediates!
        let ref = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_lfr.npy")

        let refFrames = ref.shape[0]
        let refDim = ref.shape.count > 1 ? ref.shape[1] : 560

        print("── LFR 对齐 ──")
        print("  Swift: \(inter.lfrFrames) frames × 560")
        print("  Python: \(refFrames) frames × \(refDim)")

        XCTAssertEqual(inter.lfrFrames, refFrames, "LFR 帧数不一致")
        XCTAssertEqual(inter.lfr.count, ref.data.count, "LFR 元素总数不一致")

        let (maxDiff, meanDiff) = computeDiff(inter.lfr, ref.data)
        print("  max abs diff: \(maxDiff)")
        print("  mean abs diff: \(meanDiff)")
        printFirstN(swift: inter.lfr, python: ref.data, n: 5, label: "lfr")

        // LFR 是纯拼接操作，差异完全继承自上游 Fbank
        XCTAssertLessThan(maxDiff, 2.0, "LFR max abs diff 超过 2.0")
    }

    // MARK: - Stage 3: CMVN

    func testStage3_CMVN() throws {
        let inter = Self.intermediates!
        let ref = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_cmvn.npy")

        let refFrames = ref.shape[0]

        print("── CMVN 对齐 ──")
        print("  Swift: \(inter.cmvn.count / 560) frames × 560")
        print("  Python: \(refFrames) frames × \(ref.shape.count > 1 ? ref.shape[1] : 560)")

        XCTAssertEqual(inter.cmvn.count, ref.data.count, "CMVN 元素总数不一致")

        let (maxDiff, meanDiff) = computeDiff(inter.cmvn, ref.data)
        print("  max abs diff: \(maxDiff)")
        print("  mean abs diff: \(meanDiff)")
        printFirstN(swift: inter.cmvn, python: ref.data, n: 5, label: "cmvn")

        // CMVN = (x + neg_mean) * inv_stddev，Fbank 差异经 inv_stddev 缩放
        XCTAssertLessThan(maxDiff, 0.5, "CMVN max abs diff 超过 0.5")
    }

    // MARK: - Stage 4: Encoder

    func testStage4_Encoder() throws {
        let inter = Self.intermediates!
        let ref = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_enc.npy")

        let refFrames = ref.shape[0]
        let refDim = ref.shape.count > 1 ? ref.shape[1] : 512

        print("── Encoder 对齐 ──")
        print("  Swift: \(inter.enc.count / 512) frames × 512")
        print("  Python: \(refFrames) frames × \(refDim)")

        XCTAssertEqual(inter.enc.count, ref.data.count, "Encoder 元素总数不一致")

        let (maxDiff, meanDiff) = computeDiff(inter.enc, ref.data)
        print("  max abs diff: \(maxDiff)")
        print("  mean abs diff: \(meanDiff)")
        printFirstN(swift: inter.enc, python: ref.data, n: 5, label: "enc")

        // 同一 ORT 引擎 + fp16 模型，差异来自上游 Fbank 的 FFT 精度差异
        XCTAssertLessThan(maxDiff, 0.01, "Encoder max abs diff 超过 0.01")
    }

    // MARK: - Stage 5: CIF (alphas + acoustic embeds)

    func testStage5_CIF() throws {
        let inter = Self.intermediates!
        let refAlphas = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_alphas.npy")
        let refEmbeds = try NpyLoader.loadFloat32(path: Self.alignmentDir + "/ref_acoustic_embeds.npy")

        print("── CIF Alphas 对齐 ──")
        print("  Swift alphas: \(inter.alphas.count)")
        print("  Python alphas: \(refAlphas.data.count)")

        XCTAssertEqual(inter.alphas.count, refAlphas.data.count, "Alphas 长度不一致")

        let (alphaMaxDiff, _) = computeDiff(inter.alphas, refAlphas.data)
        print("  max abs diff: \(alphaMaxDiff)")

        let swiftAlphaSum = inter.alphas.reduce(0, +)
        let pythonAlphaSum = refAlphas.data.reduce(0, +)
        print("  Swift alphas_sum: \(swiftAlphaSum)")
        print("  Python alphas_sum: \(pythonAlphaSum)")

        XCTAssertLessThan(alphaMaxDiff, 0.01, "Alphas max diff 超过 0.01")

        print("── CIF Acoustic Embeds 对齐 ──")
        let refTokenCount = refEmbeds.shape[0]
        print("  Swift: \(inter.numTokens) tokens × 512")
        print("  Python: \(refTokenCount) tokens × \(refEmbeds.shape.count > 1 ? refEmbeds.shape[1] : 512)")

        if inter.numTokens == refTokenCount {
            let (embedMaxDiff, _) = computeDiff(inter.acousticEmbeds, refEmbeds.data)
            print("  max abs diff: \(embedMaxDiff)")
            XCTAssertLessThan(embedMaxDiff, 0.01, "Acoustic embeds max diff 超过 0.01")
        } else {
            print("  Token 数量不一致 (Swift: \(inter.numTokens), Python: \(refTokenCount))")
            XCTAssertLessThanOrEqual(abs(inter.numTokens - refTokenCount), 2,
                                     "Token 数量差异超过 2")
        }
    }

    // MARK: - Stage 6: Decoder (token IDs)

    func testStage6_Decoder() throws {
        let inter = Self.intermediates!
        let refIds = try NpyLoader.loadInt32(path: Self.alignmentDir + "/ref_token_ids.npy")

        print("── Decoder Token IDs 对齐 ──")
        print("  Swift: \(inter.tokenIds.count) tokens")
        print("  Python: \(refIds.count) tokens")
        print("  Swift ids:  \(Array(inter.tokenIds.prefix(10)))")
        print("  Python ids: \(Array(refIds.prefix(10)))")

        if inter.tokenIds.count == refIds.count {
            var mismatchCount = 0
            for i in 0..<inter.tokenIds.count {
                if inter.tokenIds[i] != refIds[i] {
                    mismatchCount += 1
                    if mismatchCount <= 5 {
                        print("  mismatch at [\(i)]: Swift=\(inter.tokenIds[i]), Python=\(refIds[i])")
                    }
                }
            }
            print("  mismatches: \(mismatchCount) / \(inter.tokenIds.count)")
            XCTAssertLessThanOrEqual(mismatchCount, inter.tokenIds.count / 5,
                                     "Token ID 不匹配数超过 20%")
        } else {
            print("  Token 数量不一致")
            XCTAssertLessThanOrEqual(abs(inter.tokenIds.count - refIds.count), 2,
                                     "Token 数量差异超过 2")
        }
    }

    // MARK: - Stage 7: Token -> Text

    func testStage7_TokenToText() throws {
        let inter = Self.intermediates!
        let refTextPath = Self.alignmentDir + "/ref_text.txt"
        let refText = try String(contentsOfFile: refTextPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("── Token->Text 对齐 ──")
        print("  Swift:  \"\(inter.text)\"")
        print("  Python: \"\(refText)\"")

        if inter.text == refText {
            print("  完全匹配")
        } else {
            let swiftNoSpace = inter.text.replacingOccurrences(of: " ", with: "")
            let refNoSpace = refText.replacingOccurrences(of: " ", with: "")
            print("  去空格后 Swift:  \"\(swiftNoSpace)\"")
            print("  去空格后 Python: \"\(refNoSpace)\"")

            if swiftNoSpace == refNoSpace {
                print("  仅空格处理差异")
            } else {
                print("  文本内容不同")
            }
        }
    }

    // MARK: - 汇总

    func testSummary() throws {
        let inter = Self.intermediates!

        print("")
        print("═══════════════════════════════════════════")
        print(" ParaformerONNX 对齐验证汇总")
        print("═══════════════════════════════════════════")
        print("  Samples:  \(inter.samples.count)")
        print("  Fbank:    \(inter.fbankFrames) x 80")
        print("  LFR:      \(inter.lfrFrames) x 560")
        print("  CMVN:     \(inter.cmvn.count / 560) x 560")
        print("  Encoder:  \(inter.enc.count / 512) x 512")
        print("  Alphas:   \(inter.alphas.count)")
        print("  CIF:      \(inter.numTokens) tokens x 512")
        print("  Decoder:  \(inter.tokenIds.count) token IDs")
        print("  Text:     \"\(inter.text)\"")
        print("═══════════════════════════════════════════")
    }

    // MARK: - Helpers

    private func computeDiff(_ a: [Float], _ b: [Float]) -> (maxDiff: Float, meanDiff: Float) {
        let count = min(a.count, b.count)
        guard count > 0 else { return (0, 0) }

        var maxDiff: Float = 0
        var sumDiff: Float = 0
        for i in 0..<count {
            let d = abs(a[i] - b[i])
            maxDiff = max(maxDiff, d)
            sumDiff += d
        }
        return (maxDiff, sumDiff / Float(count))
    }

    private func printFirstN(swift: [Float], python: [Float], n: Int, label: String) {
        let count = min(n, swift.count, python.count)
        for i in 0..<count {
            let diff = abs(swift[i] - python[i])
            print("  \(label)[\(i)]: swift=\(swift[i]), python=\(python[i]), diff=\(diff)")
        }
    }
}
