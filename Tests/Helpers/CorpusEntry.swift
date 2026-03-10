import Foundation

/// 测试语料条目（对应 corpus.json 中的 entry）
struct CorpusEntry: Codable {
    let id: String
    let category: String
    let expectedTexts: [String]
    let matchMode: String
    let audioFiles: [String: String]
    let durationSec: Double
    let language: String
    let matchKeywords: [String]?
    let matchThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case id, category, language
        case expectedTexts = "expected_text"
        case matchMode = "match_mode"
        case audioFiles = "audio_files"
        case durationSec = "duration_sec"
        case matchKeywords = "match_keywords"
        case matchThreshold = "match_threshold"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(String.self, forKey: .category)
        matchMode = try container.decode(String.self, forKey: .matchMode)
        audioFiles = try container.decode([String: String].self, forKey: .audioFiles)
        durationSec = try container.decode(Double.self, forKey: .durationSec)
        language = try container.decode(String.self, forKey: .language)
        matchKeywords = try container.decodeIfPresent([String].self, forKey: .matchKeywords)
        matchThreshold = try container.decodeIfPresent(Double.self, forKey: .matchThreshold)

        // expected_text: 支持 string 或 [string]
        if let array = try? container.decode([String].self, forKey: .expectedTexts) {
            expectedTexts = array
        } else {
            let single = try container.decode(String.self, forKey: .expectedTexts)
            expectedTexts = [single]
        }
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
