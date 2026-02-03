import Foundation

/// 下载源
enum DownloadSource: CaseIterable {
    case modelScope
    case github

    var url: String {
        switch self {
        case .modelScope:
            return "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17.tar.bz2"
        case .github:
            return "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17.tar.bz2"
        }
    }

    var displayName: String {
        switch self {
        case .modelScope: return "ModelScope"
        case .github: return "GitHub"
        }
    }
}

/// FunASR Nano 模型管理器
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
    /// 当前下载源
    private var currentSource: DownloadSource?
    /// 备用下载源
    private var fallbackSource: DownloadSource?

    /// 模型存储根目录
    private let modelsDirectory: URL = {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models")
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
        return appSupportPath
    }()

    /// 模型配置
    static let modelId = "sense-voice-funasr-nano"
    static let folderName = "sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17"
    static let displayName = "SenseVoice FunASR Nano"

    /// VAD 模型配置
    static let vadModelName = "silero_vad.onnx"
    static let vadDownloadURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

    /// 获取 VAD 模型路径
    func getVADModelPath() -> String? {
        let vadPath = modelsDirectory.appendingPathComponent(Self.vadModelName)
        guard FileManager.default.fileExists(atPath: vadPath.path) else {
            return nil
        }
        return vadPath.path
    }

    /// 检查 VAD 模型是否已下载
    func isVADModelDownloaded() -> Bool {
        return getVADModelPath() != nil
    }

    /// 下载 VAD 模型
    func downloadVADModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: Self.vadDownloadURL) else {
            completion(false, "无效的下载地址")
            return
        }

        let destPath = modelsDirectory.appendingPathComponent(Self.vadModelName)

        // 如果已存在，直接返回成功
        if FileManager.default.fileExists(atPath: destPath.path) {
            completion(true, nil)
            return
        }

        progress("正在下载 VAD 模型...")

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "下载失败: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    completion(false, "下载失败: 无法获取临时文件")
                    return
                }

                do {
                    // 移动到目标位置
                    if FileManager.default.fileExists(atPath: destPath.path) {
                        try FileManager.default.removeItem(at: destPath)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destPath)
                    print("[SherpaOnnx] VAD 模型下载完成: \(destPath.path)")
                    completion(true, nil)
                } catch {
                    completion(false, "保存失败: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }

    /// 获取模型路径
    func getModelPath() -> (modelPath: String, tokensPath: String)? {
        let modelDir = modelsDirectory.appendingPathComponent(Self.folderName)
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx")
        let tokensPath = modelDir.appendingPathComponent("tokens.txt")

        guard FileManager.default.fileExists(atPath: modelPath.path),
              FileManager.default.fileExists(atPath: tokensPath.path) else {
            return nil
        }

        return (modelPath.path, tokensPath.path)
    }

    /// 检查模型是否已下载
    func isModelDownloaded() -> Bool {
        return getModelPath() != nil
    }

    /// 选择最快的下载源
    private func selectFastestSource() async -> DownloadSource {
        print("[SherpaOnnx] 正在检测最快下载源...")

        return await withTaskGroup(of: (DownloadSource, Bool).self) { group in
            let timeout: TimeInterval = 5.0

            for source in DownloadSource.allCases {
                group.addTask {
                    guard let url = URL(string: source.url) else {
                        return (source, false)
                    }
                    var request = URLRequest(url: url, timeoutInterval: timeout)
                    request.httpMethod = "HEAD"

                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse,
                           (200...399).contains(httpResponse.statusCode) {
                            print("[SherpaOnnx] \(source.displayName) 响应成功")
                            return (source, true)
                        }
                    } catch {
                        print("[SherpaOnnx] \(source.displayName) 请求失败: \(error.localizedDescription)")
                    }
                    return (source, false)
                }
            }

            // 返回第一个成功的
            for await (source, success) in group {
                if success {
                    print("[SherpaOnnx] 选择下载源: \(source.displayName)")
                    group.cancelAll()
                    return source
                }
            }

            // 都失败，默认 ModelScope
            print("[SherpaOnnx] 检测失败，默认使用 ModelScope")
            return .modelScope
        }
    }

    /// 下载模型
    func downloadModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        Task {
            // 1. 检测最快源
            await MainActor.run {
                progress("正在检测最佳下载源...")
            }

            let primarySource = await selectFastestSource()
            let fallback: DownloadSource = primarySource == .modelScope ? .github : .modelScope

            // 2. 开始下载
            await MainActor.run {
                self.startDownload(
                    from: primarySource,
                    fallback: fallback,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    /// 从指定源开始下载
    private func startDownload(
        from source: DownloadSource,
        fallback: DownloadSource,
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let url = URL(string: source.url) else {
            completion(false, "无效的下载地址")
            return
        }

        self.progressCallback = progress
        self.completionCallback = completion
        self.currentModelName = Self.displayName
        self.currentSource = source
        self.fallbackSource = fallback

        progress("正在从 \(source.displayName) 下载 \(Self.displayName)...")

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
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let modelName = currentModelName ?? "模型"
        let sourceName = currentSource?.displayName ?? ""

        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let percentage = Int(progress * 100)
            let downloaded = formatBytes(totalBytesWritten)
            let total = formatBytes(totalBytesExpectedToWrite)
            progressCallback?("正在从 \(sourceName) 下载 \(modelName)... \(percentage)% (\(downloaded) / \(total))")
        } else {
            let downloaded = formatBytes(totalBytesWritten)
            progressCallback?("正在从 \(sourceName) 下载 \(modelName)... \(downloaded)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        progressCallback?("正在解压模型...")

        let result = extractTarBz2(from: location, to: modelsDirectory)

        if result {
            completionCallback?(true, nil)
        } else {
            completionCallback?(false, "解压失败")
        }

        cleanup()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // 如果有备用源，尝试回退
            if let fallback = fallbackSource,
               let progress = progressCallback,
               let completion = completionCallback {
                print("[SherpaOnnx] 下载失败，尝试备用源: \(fallback.displayName)")
                progress("下载失败，正在尝试备用源...")
                fallbackSource = nil  // 清除，避免无限重试
                startDownload(from: fallback, fallback: fallback, progress: progress, completion: completion)
                return
            }

            completionCallback?(false, "下载失败: \(error.localizedDescription)")
            cleanup()
        }
    }

    private func cleanup() {
        currentModelName = nil
        currentDownloadTask = nil
        currentSource = nil
        fallbackSource = nil
        progressCallback = nil
        completionCallback = nil
    }
}
