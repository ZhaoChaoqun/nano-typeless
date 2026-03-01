import Foundation

/// 中文 BERT 字符级分词器
///
/// 从 vocab.txt 加载词表，将中文文本逐字符转换为 token IDs。
/// 用于 macbert4csc 模型的输入预处理和输出解码。
class BertTokenizer {
    private let token2id: [String: Int32]
    private let id2token: [Int32: String]

    static let clsToken = "[CLS]"
    static let sepToken = "[SEP]"
    static let unkToken = "[UNK]"
    static let padToken = "[PAD]"

    let clsId: Int32
    let sepId: Int32
    let unkId: Int32
    let padId: Int32
    let vocabSize: Int

    init?(vocabPath: String) {
        guard let content = try? String(contentsOfFile: vocabPath, encoding: .utf8) else {
            return nil
        }

        var t2i = [String: Int32]()
        var i2t = [Int32: String]()
        var maxId: Int32 = 0

        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            let id = Int32(index)
            t2i[token] = id
            i2t[id] = token
            maxId = max(maxId, id)
        }

        self.token2id = t2i
        self.id2token = i2t
        self.vocabSize = Int(maxId) + 1
        self.clsId = t2i[Self.clsToken] ?? 101
        self.sepId = t2i[Self.sepToken] ?? 102
        self.unkId = t2i[Self.unkToken] ?? 100
        self.padId = t2i[Self.padToken] ?? 0
    }

    /// 将文本分词为 token IDs（字符级），自动添加 [CLS] 和 [SEP]
    func tokenize(_ text: String) -> [Int32] {
        var ids: [Int32] = [clsId]

        for char in text {
            let s = String(char)
            if let id = token2id[s] {
                ids.append(id)
            } else if let id = token2id[s.lowercased()] {
                ids.append(id)
            } else {
                ids.append(unkId)
            }
        }

        ids.append(sepId)
        return ids
    }

    /// 将 token IDs 解码为文本（不含 [CLS]、[SEP]、[PAD]）
    func decode(_ ids: [Int32]) -> String {
        var result = ""
        for id in ids {
            if id == clsId || id == sepId || id == padId { continue }
            if let token = id2token[id] {
                result += token
            }
        }
        return result
    }

    /// 检查字符是否为中文字符
    static func isChinese(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        // CJK Unified Ideographs 及扩展区
        return (value >= 0x4E00 && value <= 0x9FFF) ||
               (value >= 0x3400 && value <= 0x4DBF) ||
               (value >= 0x20000 && value <= 0x2A6DF) ||
               (value >= 0x2A700 && value <= 0x2B73F) ||
               (value >= 0x2B740 && value <= 0x2B81F) ||
               (value >= 0x2B820 && value <= 0x2CEAF) ||
               (value >= 0xF900 && value <= 0xFAFF) ||
               (value >= 0x2F800 && value <= 0x2FA1F)
    }
}
