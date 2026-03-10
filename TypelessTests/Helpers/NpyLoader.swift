import Foundation

/// 最小化 .npy 文件读取器，用于加载 Python numpy 生成的参考数据
enum NpyLoader {
    struct NpyArray {
        let shape: [Int]
        let data: [Float]
    }

    enum NpyError: Error, CustomStringConvertible {
        case invalidMagic
        case unsupportedFormat(String)
        case readFailed(String)

        var description: String {
            switch self {
            case .invalidMagic: return "NpyLoader: invalid .npy magic bytes"
            case .unsupportedFormat(let msg): return "NpyLoader: unsupported format: \(msg)"
            case .readFailed(let msg): return "NpyLoader: read failed: \(msg)"
            }
        }
    }

    /// 加载 float32 .npy 文件，返回 flat [Float] 数组和 shape
    static func loadFloat32(path: String) throws -> NpyArray {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let (header, dataOffset) = try parseHeader(data)

        guard header.descr == "<f4" || header.descr == "f4" else {
            throw NpyError.unsupportedFormat("expected <f4, got \(header.descr)")
        }

        let totalElements = header.shape.reduce(1, *)
        let expectedBytes = totalElements * 4
        let available = data.count - dataOffset
        guard available >= expectedBytes else {
            throw NpyError.readFailed("need \(expectedBytes) bytes, have \(available)")
        }

        var floats = [Float](repeating: 0, count: totalElements)
        data.withUnsafeBytes { rawBuf in
            let src = rawBuf.baseAddress!.advanced(by: dataOffset)
            _ = floats.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, src, expectedBytes)
            }
        }

        return NpyArray(shape: header.shape, data: floats)
    }

    /// 加载 int32 .npy 文件，返回 [Int32] 数组
    static func loadInt32(path: String) throws -> [Int32] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let (header, dataOffset) = try parseHeader(data)

        guard header.descr == "<i4" || header.descr == "i4" else {
            throw NpyError.unsupportedFormat("expected <i4, got \(header.descr)")
        }

        let totalElements = header.shape.reduce(1, *)
        let expectedBytes = totalElements * 4
        let available = data.count - dataOffset
        guard available >= expectedBytes else {
            throw NpyError.readFailed("need \(expectedBytes) bytes, have \(available)")
        }

        var ints = [Int32](repeating: 0, count: totalElements)
        data.withUnsafeBytes { rawBuf in
            let src = rawBuf.baseAddress!.advanced(by: dataOffset)
            _ = ints.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, src, expectedBytes)
            }
        }

        return ints
    }

    // MARK: - Header parsing

    private struct NpyHeader {
        let descr: String
        let shape: [Int]
    }

    private static func parseHeader(_ data: Data) throws -> (NpyHeader, Int) {
        // Magic: \x93NUMPY
        guard data.count >= 10 else { throw NpyError.invalidMagic }
        guard data[0] == 0x93,
              data[1] == 0x4E, // N
              data[2] == 0x55, // U
              data[3] == 0x4D, // M
              data[4] == 0x50, // P
              data[5] == 0x59  // Y
        else { throw NpyError.invalidMagic }

        let majorVersion = data[6]

        var headerLen: Int
        var headerStart: Int

        if majorVersion == 1 {
            // Version 1: 2-byte header length (uint16 LE)
            headerLen = Int(data[8]) | (Int(data[9]) << 8)
            headerStart = 10
        } else if majorVersion == 2 {
            // Version 2: 4-byte header length (uint32 LE)
            guard data.count >= 12 else { throw NpyError.invalidMagic }
            headerLen = Int(data[8]) | (Int(data[9]) << 8) | (Int(data[10]) << 16) | (Int(data[11]) << 24)
            headerStart = 12
        } else {
            throw NpyError.unsupportedFormat("npy version \(majorVersion)")
        }

        guard data.count >= headerStart + headerLen else {
            throw NpyError.readFailed("header truncated")
        }

        let headerData = data[headerStart..<(headerStart + headerLen)]
        guard let headerStr = String(data: headerData, encoding: .ascii) else {
            throw NpyError.readFailed("header not ASCII")
        }

        let descr = try extractValue(from: headerStr, key: "descr")
        let shapeStr = try extractValue(from: headerStr, key: "shape")
        let shape = parseShape(shapeStr)

        return (NpyHeader(descr: descr, shape: shape), headerStart + headerLen)
    }

    /// 从 Python dict 字符串中提取 key 对应的 value
    private static func extractValue(from header: String, key: String) throws -> String {
        // Pattern: 'key': 'value' or 'key': (value)
        guard let keyRange = header.range(of: "'\(key)'") else {
            throw NpyError.readFailed("key '\(key)' not found in header")
        }
        let afterKey = header[keyRange.upperBound...]
        guard let colonIdx = afterKey.firstIndex(of: ":") else {
            throw NpyError.readFailed("no colon after key '\(key)'")
        }
        let valueStart = afterKey[afterKey.index(after: colonIdx)...].drop(while: { $0 == " " })

        if valueStart.first == "'" {
            // String value: '...'
            let inner = valueStart.dropFirst()
            guard let endQuote = inner.firstIndex(of: "'") else {
                throw NpyError.readFailed("unterminated string for '\(key)'")
            }
            return String(inner[inner.startIndex..<endQuote])
        } else if valueStart.first == "(" {
            // Tuple value: (...)
            guard let endParen = valueStart.firstIndex(of: ")") else {
                throw NpyError.readFailed("unterminated tuple for '\(key)'")
            }
            return String(valueStart[valueStart.index(after: valueStart.startIndex)...endParen])
        } else {
            // Other value
            let end = valueStart.firstIndex(of: ",") ?? valueStart.firstIndex(of: "}") ?? valueStart.endIndex
            return String(valueStart[valueStart.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// 解析 shape 元组字符串 "(79, 560)" → [79, 560]
    private static func parseShape(_ s: String) -> [Int] {
        let cleaned = s.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty {
            return []
        }

        return cleaned.split(separator: ",").compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Int(trimmed)
        }
    }
}
