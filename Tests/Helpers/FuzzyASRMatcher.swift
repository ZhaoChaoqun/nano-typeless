import Foundation

/// ASR 识别结果的模糊匹配工具
struct FuzzyASRMatcher {

    enum MatchMode {
        case exact
        case contains
        case containsAll([String])
        case emptyOrWhitespace
        case characterErrorRate(max: Double)
    }

    /// 检查识别结果是否匹配期望
    static func matches(actual: String, expected: String, mode: MatchMode) -> Bool {
        let normalizedActual = normalize(actual)
        let normalizedExpected = normalize(expected)

        switch mode {
        case .exact:
            return normalizedActual == normalizedExpected

        case .contains:
            return normalizedActual.contains(normalizedExpected)

        case .containsAll(let keywords):
            let lowerActual = actual.lowercased()
            return keywords.allSatisfy { keyword in
                lowerActual.contains(keyword.lowercased())
            }

        case .emptyOrWhitespace:
            return actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .characterErrorRate(let maxCER):
            let cer = computeCER(actual: normalizedActual, expected: normalizedExpected)
            return cer <= maxCER
        }
    }

    /// 从 CorpusEntry 构建匹配模式
    static func matchMode(for entry: CorpusEntry) -> MatchMode {
        switch entry.matchMode {
        case "exact":
            return .exact
        case "contains":
            return .contains
        case "contains_all":
            return .containsAll(entry.matchKeywords ?? [])
        case "empty_or_whitespace":
            return .emptyOrWhitespace
        case "character_error_rate":
            return .characterErrorRate(max: entry.matchThreshold ?? 0.3)
        default:
            return .characterErrorRate(max: 0.3)
        }
    }

    /// 多候选匹配：遍历所有期望文本，任一匹配即视为通过
    static func matches(actual: String, expectedTexts: [String], mode: MatchMode) -> Bool {
        guard !expectedTexts.isEmpty else { return false }
        return expectedTexts.contains { matches(actual: actual, expected: $0, mode: mode) }
    }

    /// 多候选最小 CER
    static func computeMinCER(actual: String, expectedTexts: [String]) -> Double {
        guard !expectedTexts.isEmpty else { return 1.0 }
        return expectedTexts.map { computeCER(actual: normalize(actual), expected: normalize($0)) }.min() ?? 1.0
    }

    // MARK: - 内部工具

    /// 标准化文本：去标点、去空白、小写
    static func normalize(_ text: String) -> String {
        var result = text

        // 去除中英文标点
        let zhPunct = "\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{3001}\u{FF1B}\u{FF1A}" // ，。！？、；：
            + "\u{201C}\u{201D}\u{2018}\u{2019}" // ""''
            + "\u{FF08}\u{FF09}\u{3010}\u{3011}\u{300A}\u{300B}" // （）【】《》
        let enPunct = ",.!?;:'\"()[]<>"
        let misc = "\u{2026}\u{2014}\u{2013}\u{00B7}" // …—–·
        let punctuation = CharacterSet(charactersIn: zhPunct + enPunct + misc)
        result = result.unicodeScalars
            .filter { !punctuation.contains($0) }
            .map { String($0) }
            .joined()

        // 小写
        result = result.lowercased()

        // 去除所有空白
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .joined()

        return result
    }

    /// 计算字符错误率 (CER) = Levenshtein距离 / 期望长度
    static func computeCER(actual: String, expected: String) -> Double {
        guard !expected.isEmpty else {
            return actual.isEmpty ? 0.0 : 1.0
        }

        let distance = levenshteinDistance(Array(actual), Array(expected))
        return Double(distance) / Double(expected.count)
    }

    /// Levenshtein 编辑距离
    static func levenshteinDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,         // 删除
                    curr[j - 1] + 1,     // 插入
                    prev[j - 1] + cost   // 替换
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
