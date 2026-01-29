import Foundation

/// Sherpa-ONNX 语音识别管理器
/// 支持 Paraformer 和 SenseVoice 模型
class SherpaOnnxManager: NSObject {
    static let shared = SherpaOnnxManager()

    /// 下载进度回调
    private var progressCallback: ((String) -> Void)?
    /// 下载完成回调
    private var completionCallback: ((Bool, String?) -> Void)?
    /// 当前下载的模型名称
    private var currentModelName: String?
    /// 当前下载任务
    private var currentDownloadTask: URLSessionDownloadTask?
    /// 临时文件保存路径
    private var tempFileURL: URL?

    /// 模型存储根目录 (使用 Application Support 目录，避免触发文稿文件夹访问弹窗)
    private let modelsDirectory: URL = {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Typeless/models")
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
        return appSupportPath
    }()

    /// Paraformer 模型信息
    struct ParaformerModel {
        static let modelName = "sherpa-onnx-paraformer-zh-2024-03-09"
        static let downloadURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2"

        let modelPath: String
        let tokensPath: String
    }

    /// SenseVoice 模型信息
    struct SenseVoiceModel {
        static let modelName = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        static let downloadURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2"

        let modelPath: String
        let tokensPath: String
    }

    /// 获取 Paraformer 模型路径
    func getParaformerModelPath() -> ParaformerModel? {
        let modelDir = modelsDirectory.appendingPathComponent(ParaformerModel.modelName)
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx")
        let tokensPath = modelDir.appendingPathComponent("tokens.txt")

        guard FileManager.default.fileExists(atPath: modelPath.path),
              FileManager.default.fileExists(atPath: tokensPath.path) else {
            return nil
        }

        return ParaformerModel(modelPath: modelPath.path, tokensPath: tokensPath.path)
    }

    /// 获取 SenseVoice 模型路径
    func getSenseVoiceModelPath() -> SenseVoiceModel? {
        let modelDir = modelsDirectory.appendingPathComponent(SenseVoiceModel.modelName)
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx")
        let tokensPath = modelDir.appendingPathComponent("tokens.txt")

        guard FileManager.default.fileExists(atPath: modelPath.path),
              FileManager.default.fileExists(atPath: tokensPath.path) else {
            return nil
        }

        return SenseVoiceModel(modelPath: modelPath.path, tokensPath: tokensPath.path)
    }

    /// 检查模型是否已下载
    func isModelDownloaded(_ modelId: String) -> Bool {
        switch modelId {
        case "paraformer":
            return getParaformerModelPath() != nil
        case "sensevoice-small":
            return getSenseVoiceModelPath() != nil
        default:
            return false
        }
    }

    /// 获取模型目录
    func getModelDirectory(for modelId: String) -> URL {
        switch modelId {
        case "paraformer":
            return modelsDirectory.appendingPathComponent(ParaformerModel.modelName)
        case "sensevoice-small":
            return modelsDirectory.appendingPathComponent(SenseVoiceModel.modelName)
        default:
            return modelsDirectory
        }
    }

    /// 下载模型
    func downloadModel(_ modelId: String, progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        let downloadURL: String
        let modelName: String

        switch modelId {
        case "paraformer":
            downloadURL = ParaformerModel.downloadURL
            modelName = ParaformerModel.modelName
        case "sensevoice-small":
            downloadURL = SenseVoiceModel.downloadURL
            modelName = SenseVoiceModel.modelName
        default:
            completion(false, "未知模型类型")
            return
        }

        guard let url = URL(string: downloadURL) else {
            completion(false, "无效的下载地址")
            return
        }

        // 保存回调和模型名称
        self.progressCallback = progress
        self.completionCallback = completion
        self.currentModelName = modelName

        progress("正在下载 \(modelName)...")

        // 创建带委托的 URLSession
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        let task = session.downloadTask(with: url)
        self.currentDownloadTask = task
        task.resume()
    }

    /// 格式化文件大小
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1fMB", mb)
        } else {
            return String(format: "%.0fKB", kb)
        }
    }

    /// 解压 tar.bz2 文件
    private func extractTarBz2(from sourceURL: URL, to destDir: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", sourceURL.path, "-C", destDir.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("解压失败: \(error)")
            return false
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension SherpaOnnxManager: URLSessionDownloadDelegate {
    /// 下载进度更新
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let modelName = currentModelName ?? "模型"

        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let percentage = Int(progress * 100)
            let downloaded = formatBytes(totalBytesWritten)
            let total = formatBytes(totalBytesExpectedToWrite)
            progressCallback?("正在下载 \(modelName)... \(percentage)% (\(downloaded) / \(total))")
        } else {
            let downloaded = formatBytes(totalBytesWritten)
            progressCallback?("正在下载 \(modelName)... \(downloaded)")
        }
    }

    /// 下载完成
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        progressCallback?("正在解压模型...")

        // 解压到模型目录
        let result = extractTarBz2(from: location, to: modelsDirectory)

        if result {
            completionCallback?(true, nil)
        } else {
            completionCallback?(false, "解压失败")
        }

        // 清理状态
        currentModelName = nil
        currentDownloadTask = nil
        progressCallback = nil
        completionCallback = nil
    }

    /// 下载出错
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionCallback?(false, "下载失败: \(error.localizedDescription)")

            // 清理状态
            currentModelName = nil
            currentDownloadTask = nil
            progressCallback = nil
            completionCallback = nil
        }
    }
}
