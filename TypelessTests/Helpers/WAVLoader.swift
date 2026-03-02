import Foundation

/// WAV 文件加载工具
/// 将 16kHz mono 16-bit PCM WAV 文件读取为 [Float] 样本数组
struct WAVLoader {

    struct WAVInfo {
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
        let samples: [Float]
        var duration: Double {
            guard sampleRate > 0 else { return 0 }
            return Double(samples.count) / Double(sampleRate)
        }
    }

    enum WAVError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case invalidHeader
        case unsupportedFormat(String)
        case dataChunkNotFound

        var description: String {
            switch self {
            case .fileNotFound(let path): return "WAV file not found: \(path)"
            case .invalidHeader: return "Invalid WAV header (not RIFF/WAVE)"
            case .unsupportedFormat(let msg): return "Unsupported WAV format: \(msg)"
            case .dataChunkNotFound: return "No 'data' chunk found in WAV"
            }
        }
    }

    /// 从文件路径加载 WAV 为 Float 样本数组
    static func load(path: String) throws -> WAVInfo {
        guard FileManager.default.fileExists(atPath: path) else {
            throw WAVError.fileNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(data: data)
    }

    /// 解析 WAV 二进制数据
    static func parse(data: Data) throws -> WAVInfo {
        guard data.count >= 44 else {
            throw WAVError.invalidHeader
        }

        // 验证 RIFF 头
        let riff = String(data: data[0..<4], encoding: .ascii)
        let wave = String(data: data[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else {
            throw WAVError.invalidHeader
        }

        // 解析 fmt 子块
        var offset = 12
        var audioFormat: UInt16 = 0
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var dataOffset = 0
        var dataSize = 0

        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let chunkSize = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)
            }

            if chunkID == "fmt " {
                guard offset + 16 <= data.count else { break }
                audioFormat = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt16.self) }
                channels = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 10, as: UInt16.self) }
                sampleRate = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self) }
                bitsPerSample = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 22, as: UInt16.self) }
            } else if chunkID == "data" {
                dataOffset = offset + 8
                dataSize = Int(chunkSize)
                break
            }

            offset += 8 + Int(chunkSize)
            // 对齐到偶数字节
            if offset % 2 != 0 { offset += 1 }
        }

        guard dataOffset > 0, dataSize > 0 else {
            throw WAVError.dataChunkNotFound
        }

        guard audioFormat == 1 else {
            throw WAVError.unsupportedFormat("Not PCM (format=\(audioFormat))")
        }

        // 解析 PCM 数据为 Float
        let samples: [Float]
        let endOffset = min(dataOffset + dataSize, data.count)

        switch bitsPerSample {
        case 16:
            let sampleCount = (endOffset - dataOffset) / 2
            samples = (0..<sampleCount).map { i in
                let value = data.withUnsafeBytes { ptr in
                    ptr.loadUnaligned(fromByteOffset: dataOffset + i * 2, as: Int16.self)
                }
                return Float(value) / 32768.0
            }
        case 32:
            // 假设 float32
            let sampleCount = (endOffset - dataOffset) / 4
            samples = (0..<sampleCount).map { i in
                data.withUnsafeBytes { ptr in
                    ptr.loadUnaligned(fromByteOffset: dataOffset + i * 4, as: Float.self)
                }
            }
        default:
            throw WAVError.unsupportedFormat("\(bitsPerSample)-bit not supported")
        }

        // 如果是多声道，取第一声道
        let monoSamples: [Float]
        if channels > 1 {
            let channelCount = Int(channels)
            monoSamples = stride(from: 0, to: samples.count, by: channelCount).map { samples[$0] }
        } else {
            monoSamples = samples
        }

        return WAVInfo(
            sampleRate: Int(sampleRate),
            channels: Int(channels),
            bitsPerSample: Int(bitsPerSample),
            samples: monoSamples
        )
    }
}
