import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "ModelDownloader")

/// 模型下载器
///
/// 负责从 ModelScope / GitHub 下载模型文件，支持自动检测最快源、
/// 主备源切换、下载进度回调。不涉及路径解析或解压逻辑。
class ModelDownloader: NSObject {

    /// 下载源连通性检测超时（秒）
    private static let sourceDetectionTimeout: TimeInterval = 5.0

    /// 下载进度轮询间隔（秒）
    private static let progressPollInterval: TimeInterval = 0.3

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
    /// 当前下载的模型类型
    private var currentDownloadingModel: ASRModelType?

    /// 解压完成回调（由外部注入，用于 tar.bz2 解压）
    var extractionHandler: ((URL, URL) -> Bool)?

    // MARK: - 下载源检测

    /// 选择最快的 ASR 模型下载源
    func selectFastestSource(for modelType: ASRModelType) async -> DownloadSource {
        logger.info("正在检测最快下载源...")

        return await withTaskGroup(of: (DownloadSource, Bool).self) { group in
            for source in DownloadSource.allCases {
                group.addTask {
                    guard let url = URL(string: source.url(for: modelType)) else {
                        return (source, false)
                    }
                    var request = URLRequest(url: url, timeoutInterval: Self.sourceDetectionTimeout)
                    request.httpMethod = "HEAD"

                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse,
                           (200...399).contains(httpResponse.statusCode) {
                            logger.info("\(source.displayName, privacy: .public) 响应成功")
                            return (source, true)
                        }
                    } catch {
                        logger.debug("\(source.displayName, privacy: .public) 请求失败: \(error.localizedDescription, privacy: .public)")
                    }
                    return (source, false)
                }
            }

            // 返回第一个成功的
            for await (source, success) in group {
                if success {
                    logger.info("选择下载源: \(source.displayName, privacy: .public)")
                    group.cancelAll()
                    return source
                }
            }

            // 都失败，默认 ModelScope
            logger.info("检测失败，默认使用 ModelScope")
            return .modelScope
        }
    }

    /// 检测标点模型最快下载源
    func selectFastestPunctSource() async -> DownloadSource {
        return await withTaskGroup(of: (DownloadSource, Bool).self) { group in
            for source in DownloadSource.allCases {
                group.addTask {
                    let urlString = source == .modelScope ? SherpaOnnxManager.punctModelScopeURL : SherpaOnnxManager.punctGitHubURL
                    guard let url = URL(string: urlString) else {
                        return (source, false)
                    }
                    var request = URLRequest(url: url, timeoutInterval: Self.sourceDetectionTimeout)
                    request.httpMethod = "HEAD"

                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse,
                           (200...399).contains(httpResponse.statusCode) {
                            logger.info("标点模型 \(source.displayName, privacy: .public) 响应成功")
                            return (source, true)
                        }
                    } catch {
                        logger.debug("标点模型 \(source.displayName, privacy: .public) 请求失败")
                    }
                    return (source, false)
                }
            }

            for await (source, success) in group {
                if success {
                    logger.info("标点模型选择下载源: \(source.displayName, privacy: .public)")
                    group.cancelAll()
                    return source
                }
            }

            return .modelScope
        }
    }

    // MARK: - ASR 模型下载（使用 delegate 方式跟踪进度）

    /// 下载指定 ASR 模型
    func downloadModel(_ modelType: ASRModelType, progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        Task {
            await MainActor.run {
                progress("正在检测最佳下载源...")
            }

            let primarySource = await selectFastestSource(for: modelType)
            let fallback: DownloadSource = primarySource == .modelScope ? .github : .modelScope

            await MainActor.run {
                self.startDownload(
                    modelType: modelType,
                    from: primarySource,
                    fallback: fallback,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    /// 从指定源开始下载 ASR 模型
    func startDownload(
        modelType: ASRModelType,
        from source: DownloadSource,
        fallback: DownloadSource,
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let url = URL(string: source.url(for: modelType)) else {
            completion(false, "无效的下载地址")
            return
        }

        self.progressCallback = progress
        self.completionCallback = completion
        self.currentModelName = modelType.displayName
        self.currentSource = source
        self.fallbackSource = fallback
        self.currentDownloadingModel = modelType

        progress("正在从 \(source.displayName) 下载 \(modelType.displayName)...")

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        let task = session.downloadTask(with: url)
        self.currentDownloadTask = task
        task.resume()
    }

    // MARK: - 标点模型下载

    /// 从指定源下载标点模型
    func downloadPunctFromSource(
        source: DownloadSource,
        fallback: DownloadSource?,
        destDir: URL,
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let urlString = source == .modelScope ? SherpaOnnxManager.punctModelScopeURL : SherpaOnnxManager.punctGitHubURL
        guard let url = URL(string: urlString) else {
            completion(false, "无效的下载地址")
            return
        }

        progress("正在从 \(source.displayName) 下载标点模型...")

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    // 尝试备用源
                    if let fallback = fallback {
                        logger.info("标点模型下载失败，尝试备用源: \(fallback.displayName, privacy: .public)")
                        progress("下载失败，正在尝试备用源...")
                        self.downloadPunctFromSource(source: fallback, fallback: nil, destDir: destDir, progress: progress, completion: completion)
                        return
                    }
                    completion(false, "下载失败: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    completion(false, "下载失败: 无法获取临时文件")
                    return
                }

                progress("正在解压标点模型...")

                let result = self.extractionHandler?(tempURL, destDir) ?? false

                if result {
                    logger.info("标点模型下载完成")
                    completion(true, nil)
                } else {
                    completion(false, "解压失败")
                }
            }
        }
        task.resume()
    }

    // MARK: - ITN 模型下载

    /// 下载 ITN WFST 模型（从 WeTextProcessing GitHub releases 下载 ZIP 并解压）
    func downloadITNFst(destDir: URL, progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: SherpaOnnxManager.itnWfstZipURL) else {
            completion(false, "无效的下载地址")
            return
        }

        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        progress("正在下载 ITN 模型...")

        let progressSource = DispatchSource.makeTimerSource(queue: .main)

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            progressSource.cancel()

            if let error = error {
                DispatchQueue.main.async { completion(false, "ITN 模型下载失败: \(error.localizedDescription)") }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(false, "ITN 模型下载失败: 无法获取临时文件") }
                return
            }

            DispatchQueue.main.async { progress("正在解压 ITN 模型...") }

            // 解压 ZIP 到临时目录，然后复制需要的 FST 文件
            let tmpExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: tmpExtractDir, withIntermediateDirectories: true)

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", tempURL.path, "-d", tmpExtractDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    DispatchQueue.main.async { completion(false, "ITN 模型解压失败") }
                    try? FileManager.default.removeItem(at: tmpExtractDir)
                    return
                }

                // 在解压后的目录中递归查找 zh_itn_tagger.fst 和 zh_itn_verbalizer.fst
                let taggerDest = destDir.appendingPathComponent("zh_itn_tagger.fst")
                let verbalizerDest = destDir.appendingPathComponent("zh_itn_verbalizer.fst")

                let enumerator = FileManager.default.enumerator(at: tmpExtractDir, includingPropertiesForKeys: nil)
                var foundTagger = false
                var foundVerbalizer = false

                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.lastPathComponent == "zh_itn_tagger.fst" {
                        if FileManager.default.fileExists(atPath: taggerDest.path) {
                            try FileManager.default.removeItem(at: taggerDest)
                        }
                        try FileManager.default.moveItem(at: fileURL, to: taggerDest)
                        foundTagger = true
                    } else if fileURL.lastPathComponent == "zh_itn_verbalizer.fst" {
                        if FileManager.default.fileExists(atPath: verbalizerDest.path) {
                            try FileManager.default.removeItem(at: verbalizerDest)
                        }
                        try FileManager.default.moveItem(at: fileURL, to: verbalizerDest)
                        foundVerbalizer = true
                    }
                    if foundTagger && foundVerbalizer { break }
                }

                try? FileManager.default.removeItem(at: tmpExtractDir)

                if foundTagger && foundVerbalizer {
                    logger.info("ITN WFST 模型下载完成")
                    DispatchQueue.main.async { completion(true, nil) }
                } else {
                    logger.error("ITN WFST 解压后未找到 FST 文件")
                    DispatchQueue.main.async { completion(false, "ITN 模型解压后未找到 FST 文件") }
                }
            } catch {
                try? FileManager.default.removeItem(at: tmpExtractDir)
                DispatchQueue.main.async { completion(false, "ITN 模型解压失败: \(error.localizedDescription)") }
            }
        }

        progressSource.schedule(deadline: .now() + Self.progressPollInterval, repeating: Self.progressPollInterval)
        progressSource.setEventHandler {
            let written = task.countOfBytesReceived
            let expected = task.countOfBytesExpectedToReceive
            if expected > 0 {
                let pct = Int(Double(written) / Double(expected) * 100)
                let downloadedKB = String(format: "%.0f", Double(written) / 1024)
                let totalKB = String(format: "%.0f", Double(expected) / 1024)
                progress("正在下载 ITN 模型... \(pct)% (\(downloadedKB)KB / \(totalKB)KB)")
            } else if written > 0 {
                let downloadedKB = String(format: "%.0f", Double(written) / 1024)
                progress("正在下载 ITN 模型... \(downloadedKB)KB")
            }
        }
        progressSource.resume()

        task.resume()
    }

    // MARK: - CSC 模型下载

    /// 下载 CSC 模型（直接从 ModelScope 下载两个文件）
    func downloadCSCModel(destDir: URL, progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        guard let modelURL = URL(string: SherpaOnnxManager.cscModelURL),
              let vocabURL = URL(string: SherpaOnnxManager.cscVocabURL) else {
            completion(false, "无效的下载地址")
            return
        }

        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let modelDest = destDir.appendingPathComponent("model_int8.onnx")
        let vocabDest = destDir.appendingPathComponent("vocab.txt")

        // 先下载 vocab.txt（小文件），再下载 model_int8.onnx（大文件）
        progress("正在下载 CSC 词表...")

        let vocabTask = URLSession.shared.downloadTask(with: vocabURL) { tempURL, _, error in

            if let error = error {
                DispatchQueue.main.async { completion(false, "CSC 词表下载失败: \(error.localizedDescription)") }
                return
            }
            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(false, "CSC 词表下载失败") }
                return
            }

            do {
                if FileManager.default.fileExists(atPath: vocabDest.path) {
                    try FileManager.default.removeItem(at: vocabDest)
                }
                try FileManager.default.moveItem(at: tempURL, to: vocabDest)
            } catch {
                DispatchQueue.main.async { completion(false, "CSC 词表保存失败: \(error.localizedDescription)") }
                return
            }

            DispatchQueue.main.async { progress("正在下载 CSC 模型 (约98MB)...") }

            // 使用 GCD 定时器轮询下载进度
            let progressSource = DispatchSource.makeTimerSource(queue: .main)

            let modelTask = URLSession.shared.downloadTask(with: modelURL) { tempURL, _, error in
                progressSource.cancel()

                if let error = error {
                    DispatchQueue.main.async { completion(false, "CSC 模型下载失败: \(error.localizedDescription)") }
                    return
                }
                guard let tempURL = tempURL else {
                    DispatchQueue.main.async { completion(false, "CSC 模型下载失败") }
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: modelDest.path) {
                        try FileManager.default.removeItem(at: modelDest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: modelDest)
                    logger.info("CSC 模型下载完成")
                    DispatchQueue.main.async { completion(true, nil) }
                } catch {
                    DispatchQueue.main.async { completion(false, "CSC 模型保存失败: \(error.localizedDescription)") }
                }
            }

            progressSource.schedule(deadline: .now() + Self.progressPollInterval, repeating: Self.progressPollInterval)
            progressSource.setEventHandler {
                let written = modelTask.countOfBytesReceived
                let expected = modelTask.countOfBytesExpectedToReceive
                if expected > 0 {
                    let pct = Int(Double(written) / Double(expected) * 100)
                    let downloadedMB = String(format: "%.1f", Double(written) / 1024 / 1024)
                    let totalMB = String(format: "%.1f", Double(expected) / 1024 / 1024)
                    progress("正在下载 CSC 模型... \(pct)% (\(downloadedMB)MB / \(totalMB)MB)")
                } else if written > 0 {
                    let downloadedMB = String(format: "%.1f", Double(written) / 1024 / 1024)
                    progress("正在下载 CSC 模型... \(downloadedMB)MB")
                }
            }
            progressSource.resume()

            modelTask.resume()
        }
        vocabTask.resume()
    }

    // MARK: - Helpers

    /// 格式化文件大小
    func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1fMB", mb)
        } else {
            return String(format: "%.0fKB", kb)
        }
    }

    /// 清理下载状态
    func cleanup() {
        currentModelName = nil
        currentDownloadTask = nil
        currentSource = nil
        fallbackSource = nil
        currentDownloadingModel = nil
        progressCallback = nil
        completionCallback = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {
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

        let destDir = (extractionHandler != nil) ? location : location  // location is temp file
        // Use the extraction handler injected by SherpaOnnxManager
        if let handler = extractionHandler {
            // We need the modelsDirectory — get it via the manager's pathResolver
            // The handler closure captures the destination directory
            let result = handler(location, URL(fileURLWithPath: ""))
            if result {
                completionCallback?(true, nil)
            } else {
                completionCallback?(false, "解压失败")
            }
        } else {
            completionCallback?(false, "解压处理器未设置")
        }

        cleanup()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // 如果有备用源，尝试回退
            if let fallback = fallbackSource,
               let modelType = currentDownloadingModel,
               let progress = progressCallback,
               let completion = completionCallback {
                logger.info("下载失败，尝试备用源: \(fallback.displayName, privacy: .public)")
                progress("下载失败，正在尝试备用源...")
                fallbackSource = nil  // 清除，避免无限重试
                startDownload(modelType: modelType, from: fallback, fallback: fallback, progress: progress, completion: completion)
                return
            }

            completionCallback?(false, "下载失败: \(error.localizedDescription)")
            cleanup()
        }
    }
}
