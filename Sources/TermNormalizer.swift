import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "TermNormalizer")

/// 专有名词词典后处理器
///
/// 在 ASR 输出后、其他后处理（CSC/标点/Rewrite）之前执行。
/// 按顺序执行三种规则：缩写折叠 → 命名实体纠错 → 大小写强制。
class TermNormalizer {

    // MARK: - JSON Decodable Types

    private struct Dictionary: Decodable {
        let version: Int
        let rules: Rules
    }

    private struct Rules: Decodable {
        let acronyms: [AcronymEntry]
        let entities: [EntityEntry]
        let casing: [CasingEntry]
    }

    private struct AcronymEntry: Decodable {
        let expanded: String
        let canonical: String
    }

    private struct EntityEntry: Decodable {
        let patterns: [String]
        let canonical: String
    }

    private struct CasingEntry: Decodable {
        let term: String
        let canonical: String
    }

    // MARK: - Internal Representation

    private struct AcronymRule {
        let letters: [String]     // 每个字母（大写），如 ["A","P","I"]
        let canonical: String     // "API"
    }

    // MARK: - Properties

    /// 按字母数降序排列（优先匹配更长的缩写）
    private let acronymRules: [AcronymRule]
    /// 所有 entity pattern 展平后按长度降序排列
    private let entityPatterns: [(patternLower: String, canonical: String)]
    /// lowercased term -> canonical
    private let casingLookup: [String: String]

    // MARK: - Init

    /// 从 URL 加载词典
    init?(dictionaryURL: URL) {
        guard let data = try? Data(contentsOf: dictionaryURL) else {
            logger.error("词典文件读取失败: \(dictionaryURL.path, privacy: .public)")
            return nil
        }

        guard let dict = try? JSONDecoder().decode(Dictionary.self, from: data) else {
            logger.error("词典 JSON 解析失败: \(dictionaryURL.path, privacy: .public)")
            return nil
        }

        // 构建 acronym rules，按字母数降序
        self.acronymRules = dict.rules.acronyms.map { entry in
            let letters = entry.expanded.split(separator: " ").map { String($0).uppercased() }
            return AcronymRule(letters: letters, canonical: entry.canonical)
        }.sorted { $0.letters.count > $1.letters.count }

        // 展平 entity patterns，按 pattern 长度降序
        var patterns: [(String, String)] = []
        for entry in dict.rules.entities {
            for pattern in entry.patterns {
                patterns.append((pattern.lowercased(), entry.canonical))
            }
        }
        self.entityPatterns = patterns.sorted { $0.0.count > $1.0.count }

        // 构建 casing lookup
        var lookup: [String: String] = [:]
        for entry in dict.rules.casing {
            lookup[entry.term.lowercased()] = entry.canonical
        }
        self.casingLookup = lookup

        logger.info("TermNormalizer 加载成功: \(self.acronymRules.count) 条缩写, \(self.entityPatterns.count) 条实体, \(self.casingLookup.count) 条大小写规则")
    }

    /// 便利初始化：自动从 Application Support / Bundle 中查找词典
    convenience init?() {
        // 优先级 1: Application Support 目录（用户自定义）
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Nano Typeless/term_dictionary.json")

        if let appSupport = appSupport, FileManager.default.fileExists(atPath: appSupport.path) {
            logger.info("从 Application Support 加载词典")
            self.init(dictionaryURL: appSupport)
            return
        }

        // 优先级 2: App Bundle 内嵌默认词典
        if let bundleURL = Bundle.main.url(forResource: "term_dictionary", withExtension: "json") {
            logger.info("从 Bundle 加载默认词典")
            self.init(dictionaryURL: bundleURL)
            return
        }

        logger.warning("未找到词典文件 term_dictionary.json")
        return nil
    }

    // MARK: - Public API

    /// 对文本执行专有名词标准化
    func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text
        result = foldAcronyms(result)
        result = correctEntities(result)
        result = fixCasing(result)
        return result
    }

    // MARK: - Step 1: Acronym Folding

    /// 将空格分隔的单字母序列折叠为缩写
    /// 例: "A P I" -> "API", "H T T P S" -> "HTTPS"
    private func foldAcronyms(_ text: String) -> String {
        var result = text

        for rule in acronymRules {
            // 构建匹配 pattern: 字母间允许 1+ 空格，case-insensitive
            // 例: letters=["H","T","T","P","S"] -> "H\\s+T\\s+T\\s+P\\s+S"
            let regexPattern = rule.letters
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "\\s+")

            // 包裹词边界检查（前后必须是非字母字符或字符串起止）
            let fullPattern = "(?<![a-zA-Z])" + regexPattern + "(?![a-zA-Z])"

            guard let regex = try? NSRegularExpression(
                pattern: fullPattern, options: .caseInsensitive
            ) else { continue }

            // 从后向前替换避免偏移量变化
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                result = (result as NSString).replacingCharacters(in: match.range, with: rule.canonical)
            }
        }

        return result
    }

    // MARK: - Step 2: Entity Correction

    /// 多模式 case-insensitive 匹配，纠正命名实体
    /// 例: "chat GPT" -> "ChatGPT", "Iphone" -> "iPhone"
    private func correctEntities(_ text: String) -> String {
        var result = text

        for (patternLower, canonical) in entityPatterns {
            var searchStart = result.startIndex

            while searchStart < result.endIndex {
                let searchRange = searchStart..<result.endIndex
                guard let range = result.range(of: patternLower, options: .caseInsensitive, range: searchRange) else {
                    break
                }

                // 已经是 canonical 形式则跳过
                if result[range] == canonical {
                    searchStart = range.upperBound
                    continue
                }

                // 词边界检查
                if isWordBoundary(result, at: range.lowerBound) &&
                   isWordBoundary(result, at: range.upperBound) {
                    result.replaceSubrange(range, with: canonical)
                    // 替换后跳过已替换的 canonical 文本
                    let newEnd = result.index(range.lowerBound, offsetBy: canonical.count)
                    searchStart = newEnd
                } else {
                    searchStart = range.upperBound
                }
            }
        }

        return result
    }

    // MARK: - Step 3: Casing Fix

    /// 提取英文 token 并修正大小写
    /// 例: "github" -> "GitHub", "macos" -> "macOS"
    private func fixCasing(_ text: String) -> String {
        // 匹配连续的英文字母（含 . 用于 Node.js 等）
        guard let tokenRegex = try? NSRegularExpression(
            pattern: "[a-zA-Z][a-zA-Z.]*[a-zA-Z]|[a-zA-Z]", options: []
        ) else { return text }

        var result = text
        let nsString = result as NSString
        let matches = tokenRegex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

        // 倒序遍历避免偏移量变化
        for match in matches.reversed() {
            let token = nsString.substring(with: match.range)
            if let canonical = casingLookup[token.lowercased()], token != canonical {
                result = (result as NSString).replacingCharacters(in: match.range, with: canonical)
            }
        }

        return result
    }

    // MARK: - Helpers

    /// 检查给定位置是否为词边界
    /// 字符串起止、空格、标点、中文字符均算词边界
    private func isWordBoundary(_ text: String, at index: String.Index) -> Bool {
        if index == text.startIndex || index == text.endIndex {
            return true
        }

        // 检查边界前一个字符（对 lowerBound）或当前字符（对 upperBound）
        let char: Character
        if index == text.endIndex {
            char = text[text.index(before: index)]
        } else if index == text.startIndex {
            char = text[index]
        } else {
            // 对于 range.lowerBound，检查它前面的字符
            // 对于 range.upperBound，检查它指向的字符
            let prevChar = text[text.index(before: index)]
            let nextChar = text[index]
            // 如果前一个字符或后一个字符是边界字符，认为是词边界
            return isBoundaryChar(prevChar) || isBoundaryChar(nextChar)
        }

        return isBoundaryChar(char)
    }

    private func isBoundaryChar(_ char: Character) -> Bool {
        return char.isWhitespace || char.isPunctuation || Self.isChinese(char)
    }

    private static func isChinese(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)      // CJK 统一汉字
            || (0x3400...0x4DBF).contains(value)       // CJK 扩展 A
            || (0x20000...0x2A6DF).contains(value)     // CJK 扩展 B
            || (0x3000...0x303F).contains(value)       // CJK 符号和标点
            || (0xFF00...0xFFEF).contains(value)       // 全角形式
    }
}
