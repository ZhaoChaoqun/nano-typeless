import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "ModelExtractionService")

/// 模型文件解压服务
///
/// 负责 tar.bz2 归档文件的解压和文件移动。
/// 不涉及下载或路径解析逻辑。
class ModelExtractionService {

    /// 解压 tar.bz2 文件到指定目录
    /// - Parameters:
    ///   - sourceURL: tar.bz2 文件的本地路径
    ///   - destDir: 解压目标目录
    /// - Returns: 解压是否成功
    func extractTarBz2(from sourceURL: URL, to destDir: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", sourceURL.path, "-C", destDir.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("解压失败: \(error, privacy: .public)")
            return false
        }
    }
}
