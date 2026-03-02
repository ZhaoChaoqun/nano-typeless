import Foundation

/// 测试语料条目（对应 corpus.json 中的 entry）
struct CorpusEntry: Codable {
    let id: String
    let category: String
    let expectedText: String
    let matchMode: String
    let audioFiles: [String: String]
    let durationSec: Double
    let language: String
    let matchKeywords: [String]?
    let matchThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case id, category, language
        case expectedText = "expected_text"
        case matchMode = "match_mode"
        case audioFiles = "audio_files"
        case durationSec = "duration_sec"
        case matchKeywords = "match_keywords"
        case matchThreshold = "match_threshold"
    }
}

/// corpus.json 的顶层结构
struct Corpus: Codable {
    let version: Int
    let generatedAt: String
    let sampleRate: Int
    let format: String
    let entries: [CorpusEntry]

    enum CodingKeys: String, CodingKey {
        case version, format, entries
        case generatedAt = "generated_at"
        case sampleRate = "sample_rate"
    }
}
