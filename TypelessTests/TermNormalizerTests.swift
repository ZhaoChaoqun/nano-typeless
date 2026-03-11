import XCTest
@testable import Nano_Typeless

final class TermNormalizerTests: XCTestCase {

    private var normalizer: TermNormalizer!

    override func setUpWithError() throws {
        // 从 Bundle 或直接从 Sources 目录加载词典
        let bundleURL = Bundle(for: type(of: self)).url(forResource: "term_dictionary", withExtension: "json")
            ?? Bundle.main.url(forResource: "term_dictionary", withExtension: "json")

        // 如果 bundle 中找不到，直接从源码目录加载
        let url = bundleURL ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/term_dictionary.json")

        normalizer = TermNormalizer(dictionaryURL: url)
        XCTAssertNotNil(normalizer, "词典加载失败")
    }

    // MARK: - 缩写折叠

    func testAcronymFolding_basic() {
        XCTAssertEqual(normalizer.normalize("A P I"), "API")
        XCTAssertEqual(normalizer.normalize("U R L"), "URL")
        XCTAssertEqual(normalizer.normalize("S Q L"), "SQL")
    }

    func testAcronymFolding_longerFirst() {
        // HTTPS (5 letters) 应该优先匹配，不被 HTTP (4 letters) 抢占
        XCTAssertEqual(normalizer.normalize("H T T P S"), "HTTPS")
        XCTAssertEqual(normalizer.normalize("H T T P"), "HTTP")
    }

    func testAcronymFolding_specialCanonical() {
        // CI/CD 含特殊分隔符
        XCTAssertEqual(normalizer.normalize("C I C D"), "CI/CD")
    }

    func testAcronymFolding_alreadyCorrect() {
        // 已经是正确形式，不应被修改
        XCTAssertEqual(normalizer.normalize("API"), "API")
        XCTAssertEqual(normalizer.normalize("HTTP"), "HTTP")
    }

    func testAcronymFolding_mixedWithChinese() {
        XCTAssertEqual(normalizer.normalize("使用 A P I 做开发"), "使用 API 做开发")
        XCTAssertEqual(normalizer.normalize("通过H T T P请求"), "通过HTTP请求")
    }

    func testAcronymFolding_multipleInSameText() {
        XCTAssertEqual(
            normalizer.normalize("用 H T T P 和 A P I"),
            "用 HTTP 和 API"
        )
    }

    // MARK: - 实体纠错

    func testEntityCorrection_chatGPT() {
        // 先折叠 G P T，再匹配 entity pattern "chat gpt"
        XCTAssertEqual(normalizer.normalize("chat G P T"), "ChatGPT")
        XCTAssertEqual(normalizer.normalize("chatgpt"), "ChatGPT")
    }

    func testEntityCorrection_iPhone() {
        XCTAssertEqual(normalizer.normalize("Iphone"), "iPhone")
        XCTAssertEqual(normalizer.normalize("iphone"), "iPhone")
        XCTAssertEqual(normalizer.normalize("i phone"), "iPhone")
    }

    func testEntityCorrection_xcode() {
        XCTAssertEqual(normalizer.normalize("x code"), "Xcode")
        XCTAssertEqual(normalizer.normalize("X code"), "Xcode")
    }

    func testEntityCorrection_programmingLanguages() {
        XCTAssertEqual(normalizer.normalize("type script"), "TypeScript")
        XCTAssertEqual(normalizer.normalize("java script"), "JavaScript")
        XCTAssertEqual(normalizer.normalize("typescript"), "TypeScript")
    }

    func testEntityCorrection_alreadyCorrect() {
        XCTAssertEqual(normalizer.normalize("ChatGPT"), "ChatGPT")
        XCTAssertEqual(normalizer.normalize("iPhone"), "iPhone")
        XCTAssertEqual(normalizer.normalize("VS Code"), "VS Code")
    }

    func testEntityCorrection_WiFi() {
        XCTAssertEqual(normalizer.normalize("wifi"), "Wi-Fi")
        XCTAssertEqual(normalizer.normalize("WIFI"), "Wi-Fi")
        XCTAssertEqual(normalizer.normalize("wi fi"), "Wi-Fi")
    }

    // MARK: - 大小写强制

    func testCasingFix_basic() {
        XCTAssertEqual(normalizer.normalize("github"), "GitHub")
        XCTAssertEqual(normalizer.normalize("macos"), "macOS")
        XCTAssertEqual(normalizer.normalize("ios"), "iOS")
    }

    func testCasingFix_alreadyCorrect() {
        XCTAssertEqual(normalizer.normalize("GitHub"), "GitHub")
        XCTAssertEqual(normalizer.normalize("macOS"), "macOS")
    }

    func testCasingFix_wordBoundary() {
        // "reactive" 不应匹配 "react" 的 casing 规则（如果有的话）
        // 这里测试 "docker" 不匹配 "dockerize" 的子串
        let result = normalizer.normalize("使用docker部署")
        XCTAssertTrue(result.contains("Docker"))
    }

    func testCasingFix_inSentence() {
        XCTAssertEqual(
            normalizer.normalize("我在github上提交了代码"),
            "我在GitHub上提交了代码"
        )
    }

    // MARK: - 边界 case

    func testEmptyString() {
        XCTAssertEqual(normalizer.normalize(""), "")
    }

    func testPureChinese() {
        let text = "今天天气真好"
        XCTAssertEqual(normalizer.normalize(text), text)
    }

    func testMixedChineseEnglish() {
        let result = normalizer.normalize("我在用github写type script代码")
        XCTAssertTrue(result.contains("GitHub"))
        XCTAssertTrue(result.contains("TypeScript"))
    }

    // MARK: - 三阶段联动

    func testFullPipeline_chatGPT() {
        // Step 1: "G P T" -> "GPT" (acronym folding)
        // Step 2: "chat GPT" -> "ChatGPT" (entity correction)
        let result = normalizer.normalize("我在用chat G P T写代码")
        XCTAssertTrue(result.contains("ChatGPT"))
    }

    func testFullPipeline_complexSentence() {
        let input = "打开github看看chat G P T的A P I文档"
        let result = normalizer.normalize(input)
        XCTAssertTrue(result.contains("GitHub"))
        XCTAssertTrue(result.contains("ChatGPT"))
        XCTAssertTrue(result.contains("API"))
    }

    // MARK: - 词典加载失败

    func testInvalidDictionaryPath() {
        let normalizer = TermNormalizer(dictionaryURL: URL(fileURLWithPath: "/nonexistent/path.json"))
        XCTAssertNil(normalizer)
    }
}
