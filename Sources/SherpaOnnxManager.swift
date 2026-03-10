import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxManager")

/// ASR 模型类型
enum ASRModelType: String, CaseIterable, Identifiable {
    case streamingParaformer = "streaming-paraformer"
    case qwenASR = "qwen-asr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streamingParaformer:
            return "Streaming Paraformer"
        case .qwenASR:
            return "Qwen3-ASR"
        }
    }

    var description: String {
        switch self {
        case .streamingParaformer:
            return "原生流式识别，中英文混合"
        case .qwenASR:
            return "Qwen3 大模型 ASR，中英文混合，自带标点"
        }
    }

    var folderName: String {
        switch self {
        case .streamingParaformer:
            return "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
        case .qwenASR:
            return "Qwen3-ASR-0.6B"
        }
    }

    /// 是否需要外部标点模型（Qwen3-ASR 自带标点）
    var needsPunctuation: Bool {
        switch self {
        case .qwenASR:
            return false
        case .streamingParaformer:
            return true
        }
    }

    var modelSize: String {
        switch self {
        case .streamingParaformer:
            return "~414MB"
        case .qwenASR:
            return "~834MB"
        }
    }
}

/// 下载源
enum DownloadSource: CaseIterable {
    case modelScope
    case github

    func url(for model: ASRModelType) -> String {
        switch (self, model) {
        case (.modelScope, .streamingParaformer):
            return "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2"
        case (.github, .streamingParaformer):
            return "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2"
        case (.modelScope, .qwenASR):
            return "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/Qwen3-ASR-0.6B.tar.bz2"
        case (.github, .qwenASR):
            // GitHub 备用源暂无，使用 ModelScope
            return "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/Qwen3-ASR-0.6B.tar.bz2"
        }
    }

    var displayName: String {
        switch self {
        case .modelScope: return "ModelScope"
        case .github: return "GitHub"
        }
    }
}

/// 模型管理器
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
    /// 当前下载的模型类型
    private var currentDownloadingModel: ASRModelType?

    /// 模型存储根目录
    private let modelsDirectory: URL = {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models")
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
        return appSupportPath
    }()

    /// VAD 模型配置
    static let vadModelName = "silero_vad.onnx"
    static let vadDownloadURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

    /// 标点模型配置（INT8 版本，更小的模型文件）
    static let punctModelFolder = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
    static let punctModelScopeURL = "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2"
    static let punctGitHubURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2"

    /// ITN WFST 模型配置（WeTextProcessing tagger+verbalizer 两阶段中文 ITN）
    static let itnWfstFolder = "itn"
    static let itnWfstZipURL = "https://github.com/wenet-e2e/WeTextProcessing/releases/download/1.0.4/release-graph-v1.0.4.1.zip"

    /// CSC 模型配置（中文拼写纠错 macbert4csc）
    static let cscModelFolder = "macbert4csc-base-chinese"
    static let cscModelURL = "https://modelscope.cn/models/Xenova/macbert4csc-base-chinese/resolve/master/onnx/model_int8.onnx"
    static let cscVocabURL = "https://modelscope.cn/models/Xenova/macbert4csc-base-chinese/resolve/master/vocab.txt"

    /// Qwen3 Rewrite 模型配置（一站式后处理：ITN + 标点 + CSC + 术语规范化）
    static let qwen3RewriteFolder = "Qwen3-0.6B-rewrite-lora"
    static let qwen3RewriteModelURL = "https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/Qwen3-0.6B-rewrite-lora.tar.bz2"

    // MARK: - Streaming Paraformer 模型路径

    /// FP16 模型目录名（原生 ORT 推理使用）
    static let streamingParaformerFP16Folder = "sherpa-onnx-streaming-paraformer-bilingual-zh-en-fp16"

    /// 获取 Streaming Paraformer 模型路径（优先级：FP16 > INT8 > FP32）
    ///
    /// FP16 模型精度最高（与 Python 参考实现完全一致），优先使用。
    /// INT8 量化模型在短音频上存在 token 重复/乱序问题。
    func getStreamingParaformerPath() -> (encoderPath: String, decoderPath: String, tokensPath: String)? {
        // 1. 优先使用 FP16 版本（独立目录）
        let fp16Dir = modelsDirectory.appendingPathComponent(Self.streamingParaformerFP16Folder)
        let fp16Tokens = fp16Dir.appendingPathComponent("tokens.txt")
        let encoderFP16 = fp16Dir.appendingPathComponent("encoder.fp16.onnx")
        let decoderFP16 = fp16Dir.appendingPathComponent("decoder.fp16.onnx")

        if FileManager.default.fileExists(atPath: encoderFP16.path),
           FileManager.default.fileExists(atPath: decoderFP16.path),
           FileManager.default.fileExists(atPath: fp16Tokens.path) {
            return (encoderFP16.path, decoderFP16.path, fp16Tokens.path)
        }

        // 2. 回退到 INT8 版本
        let modelDir = modelsDirectory.appendingPathComponent(ASRModelType.streamingParaformer.folderName)
        let tokensPath = modelDir.appendingPathComponent("tokens.txt")

        guard FileManager.default.fileExists(atPath: tokensPath.path) else {
            return nil
        }

        let encoderINT8 = modelDir.appendingPathComponent("encoder.int8.onnx")
        let decoderINT8 = modelDir.appendingPathComponent("decoder.int8.onnx")

        if FileManager.default.fileExists(atPath: encoderINT8.path),
           FileManager.default.fileExists(atPath: decoderINT8.path) {
            return (encoderINT8.path, decoderINT8.path, tokensPath.path)
        }

        // 3. 回退到 FP32 版本
        let encoderFP32 = modelDir.appendingPathComponent("encoder.onnx")
        let decoderFP32 = modelDir.appendingPathComponent("decoder.onnx")

        if FileManager.default.fileExists(atPath: encoderFP32.path),
           FileManager.default.fileExists(atPath: decoderFP32.path) {
            return (encoderFP32.path, decoderFP32.path, tokensPath.path)
        }

        return nil
    }

    /// 检查 Streaming Paraformer 模型是否已下载
    func isStreamingParaformerDownloaded() -> Bool {
        return getStreamingParaformerPath() != nil
    }

    // MARK: - QwenASR 模型路径

    /// 获取 QwenASR 模型目录路径
    func getQwenASRModelDir() -> String? {
        let modelDir = modelsDirectory.appendingPathComponent(ASRModelType.qwenASR.folderName)

        // 检查关键文件：safetensors 权重和 vocab.json
        let vocabPath = modelDir.appendingPathComponent("vocab.json")
        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            return nil
        }

        // 检查 safetensors 权重文件（可能是单文件或分片）
        let singlePath = modelDir.appendingPathComponent("model.safetensors")
        if FileManager.default.fileExists(atPath: singlePath.path) {
            return modelDir.path
        }

        // 分片模型：检查 model-00001-of-*.safetensors
        let indexPath = modelDir.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: indexPath.path) {
            return modelDir.path
        }

        return nil
    }

    /// 检查 QwenASR 模型是否已下载
    func isQwenASRModelDownloaded() -> Bool {
        return getQwenASRModelDir() != nil
    }

    // MARK: - 通用模型检查

    /// 检查指定模型是否已下载
    func isModelDownloaded(_ modelType: ASRModelType) -> Bool {
        switch modelType {
        case .streamingParaformer:
            return isStreamingParaformerDownloaded()
        case .qwenASR:
            return isQwenASRModelDownloaded()
        }
    }

    // MARK: - VAD 模型

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
                    if FileManager.default.fileExists(atPath: destPath.path) {
                        try FileManager.default.removeItem(at: destPath)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destPath)
                    logger.info("VAD 模型下载完成: \(destPath.path, privacy: .public)")
                    completion(true, nil)
                } catch {
                    completion(false, "保存失败: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }

    // MARK: - ITN WFST 模型（WeTextProcessing 中文 ITN）

    /// 获取 ITN WFST 路径（逗号分隔的 tagger + verbalizer 路径，供 sherpa-onnx rule_fsts 使用）
    func getITNFstPath() -> String? {
        let itnDir = modelsDirectory.appendingPathComponent(Self.itnWfstFolder)
        let tagger = itnDir.appendingPathComponent("zh_itn_tagger.fst")
        let verbalizer = itnDir.appendingPathComponent("zh_itn_verbalizer.fst")

        guard FileManager.default.fileExists(atPath: tagger.path),
              FileManager.default.fileExists(atPath: verbalizer.path) else {
            return nil
        }
        return "\(tagger.path),\(verbalizer.path)"
    }

    /// 检查 ITN WFST 模型是否已下载
    func isITNFstDownloaded() -> Bool {
        return getITNFstPath() != nil
    }

    /// 下载 ITN WFST 模型（从 WeTextProcessing GitHub releases 下载 ZIP 并解压）
    func downloadITNFst(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isITNFstDownloaded() {
            completion(true, nil)
            return
        }

        guard let url = URL(string: Self.itnWfstZipURL) else {
            completion(false, "无效的下载地址")
            return
        }

        let itnDir = modelsDirectory.appendingPathComponent(Self.itnWfstFolder)
        try? FileManager.default.createDirectory(at: itnDir, withIntermediateDirectories: true)

        progress("正在下载 ITN 模型...")

        let progressSource = DispatchSource.makeTimerSource(queue: .main)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            progressSource.cancel()

            guard let self = self else { return }

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
                let taggerDest = itnDir.appendingPathComponent("zh_itn_tagger.fst")
                let verbalizerDest = itnDir.appendingPathComponent("zh_itn_verbalizer.fst")

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

        progressSource.schedule(deadline: .now() + 0.3, repeating: 0.3)
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

    // MARK: - 标点模型

    /// 获取标点模型路径
    func getPunctuationModelPath() -> String? {
        let modelDir = modelsDirectory.appendingPathComponent(Self.punctModelFolder)
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return nil
        }
        return modelPath.path
    }

    /// 检查标点模型是否已下载
    func isPunctuationModelDownloaded() -> Bool {
        return getPunctuationModelPath() != nil
    }

    /// 下载标点模型
    func downloadPunctuationModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        // 如果已存在，直接返回成功
        if isPunctuationModelDownloaded() {
            completion(true, nil)
            return
        }

        Task {
            await MainActor.run {
                progress("正在检测最佳下载源...")
            }

            // 检测最快的下载源
            let primarySource = await selectFastestPunctSource()
            let fallbackSource: DownloadSource = primarySource == .modelScope ? .github : .modelScope

            await MainActor.run {
                self.downloadPunctFromSource(
                    source: primarySource,
                    fallback: fallbackSource,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    // MARK: - CSC 模型（中文拼写纠错）

    /// 获取 CSC 模型路径
    func getCSCModelPath() -> (modelPath: String, vocabPath: String)? {
        let modelDir = modelsDirectory.appendingPathComponent(Self.cscModelFolder)
        let modelPath = modelDir.appendingPathComponent("model_int8.onnx")
        let vocabPath = modelDir.appendingPathComponent("vocab.txt")

        guard FileManager.default.fileExists(atPath: modelPath.path),
              FileManager.default.fileExists(atPath: vocabPath.path) else {
            return nil
        }
        return (modelPath.path, vocabPath.path)
    }

    /// 检查 CSC 模型是否已下载
    func isCSCModelDownloaded() -> Bool {
        return getCSCModelPath() != nil
    }

    /// 下载 CSC 模型（直接从 ModelScope 下载两个文件）
    func downloadCSCModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isCSCModelDownloaded() {
            completion(true, nil)
            return
        }

        guard let modelURL = URL(string: Self.cscModelURL),
              let vocabURL = URL(string: Self.cscVocabURL) else {
            completion(false, "无效的下载地址")
            return
        }

        let modelDir = modelsDirectory.appendingPathComponent(Self.cscModelFolder)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let modelDest = modelDir.appendingPathComponent("model_int8.onnx")
        let vocabDest = modelDir.appendingPathComponent("vocab.txt")

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

            progressSource.schedule(deadline: .now() + 0.3, repeating: 0.3)
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

    // MARK: - Qwen3 Rewrite 模型（一站式后处理）

    /// 获取 Qwen3 Rewrite 模型目录路径
    func getQwen3RewriteModelDir() -> String? {
        let modelDir = modelsDirectory.appendingPathComponent(Self.qwen3RewriteFolder)
        let modelPath = modelDir.appendingPathComponent("model_int8.qint8")
        let tokenizerPath = modelDir.appendingPathComponent("tokenizer.json")

        guard FileManager.default.fileExists(atPath: modelPath.path),
              FileManager.default.fileExists(atPath: tokenizerPath.path) else {
            return nil
        }
        return modelDir.path
    }

    /// 检查 Qwen3 Rewrite 模型是否已下载
    func isQwen3RewriteModelDownloaded() -> Bool {
        return getQwen3RewriteModelDir() != nil
    }

    /// 下载 Qwen3 Rewrite 模型（tar.bz2 格式）
    func downloadQwen3RewriteModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isQwen3RewriteModelDownloaded() {
            completion(true, nil)
            return
        }

        guard let url = URL(string: Self.qwen3RewriteModelURL) else {
            completion(false, "无效的下载地址")
            return
        }

        progress("正在下载 Qwen3 Rewrite 模型 (约570MB)...")

        let progressSource = DispatchSource.makeTimerSource(queue: .main)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            progressSource.cancel()

            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(false, "Qwen3 Rewrite 模型下载失败: \(error.localizedDescription)") }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(false, "Qwen3 Rewrite 模型下载失败: 无法获取临时文件") }
                return
            }

            DispatchQueue.main.async { progress("正在解压 Qwen3 Rewrite 模型...") }

            let result = self.extractTarBz2(from: tempURL, to: self.modelsDirectory)

            if result {
                logger.info("Qwen3 Rewrite 模型下载完成")
                DispatchQueue.main.async { completion(true, nil) }
            } else {
                DispatchQueue.main.async { completion(false, "Qwen3 Rewrite 模型解压失败") }
            }
        }

        progressSource.schedule(deadline: .now() + 0.3, repeating: 0.3)
        progressSource.setEventHandler {
            let written = task.countOfBytesReceived
            let expected = task.countOfBytesExpectedToReceive
            if expected > 0 {
                let pct = Int(Double(written) / Double(expected) * 100)
                let downloadedMB = String(format: "%.1f", Double(written) / 1024 / 1024)
                let totalMB = String(format: "%.1f", Double(expected) / 1024 / 1024)
                progress("正在下载 Qwen3 Rewrite 模型... \(pct)% (\(downloadedMB)MB / \(totalMB)MB)")
            } else if written > 0 {
                let downloadedMB = String(format: "%.1f", Double(written) / 1024 / 1024)
                progress("正在下载 Qwen3 Rewrite 模型... \(downloadedMB)MB")
            }
        }
        progressSource.resume()

        task.resume()
    }

    /// 检测标点模型最快下载源
    private func selectFastestPunctSource() async -> DownloadSource {
        return await withTaskGroup(of: (DownloadSource, Bool).self) { group in
            let timeout: TimeInterval = 5.0

            for source in DownloadSource.allCases {
                group.addTask {
                    let urlString = source == .modelScope ? Self.punctModelScopeURL : Self.punctGitHubURL
                    guard let url = URL(string: urlString) else {
                        return (source, false)
                    }
                    var request = URLRequest(url: url, timeoutInterval: timeout)
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

    /// 从指定源下载标点模型
    private func downloadPunctFromSource(
        source: DownloadSource,
        fallback: DownloadSource?,
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let urlString = source == .modelScope ? Self.punctModelScopeURL : Self.punctGitHubURL
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
                        self.downloadPunctFromSource(source: fallback, fallback: nil, progress: progress, completion: completion)
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

                let result = self.extractTarBz2(from: tempURL, to: self.modelsDirectory)

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

    // MARK: - 下载功能

    /// 选择最快的下载源
    private func selectFastestSource(for modelType: ASRModelType) async -> DownloadSource {
        logger.info("正在检测最快下载源...")

        return await withTaskGroup(of: (DownloadSource, Bool).self) { group in
            let timeout: TimeInterval = 5.0

            for source in DownloadSource.allCases {
                group.addTask {
                    guard let url = URL(string: source.url(for: modelType)) else {
                        return (source, false)
                    }
                    var request = URLRequest(url: url, timeoutInterval: timeout)
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

    /// 下载指定模型
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

    /// 从指定源开始下载
    private func startDownload(
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
            logger.error("解压失败: \(error, privacy: .public)")
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

    private func cleanup() {
        currentModelName = nil
        currentDownloadTask = nil
        currentSource = nil
        fallbackSource = nil
        currentDownloadingModel = nil
        progressCallback = nil
        completionCallback = nil
    }
}
