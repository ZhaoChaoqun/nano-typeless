import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxManager")

/// ASR 模型类型
enum ASRModelType: String, CaseIterable, Identifiable {
    case qwenASR = "qwen-asr"
    case streamingParaformer = "streaming-paraformer"
    case dualEngine = "dual-engine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streamingParaformer:
            return "Streaming Paraformer"
        case .qwenASR:
            return "Qwen3-ASR"
        case .dualEngine:
            return "双引擎"
        }
    }

    var description: String {
        switch self {
        case .streamingParaformer:
            return "原生流式识别，中英文混合"
        case .qwenASR:
            return "Qwen3 大模型 ASR，中英文混合，自带标点"
        case .dualEngine:
            return "Paraformer 实时预览 + Qwen3-ASR 精转写"
        }
    }

    var folderName: String {
        switch self {
        case .streamingParaformer:
            return "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
        case .qwenASR:
            return "Qwen3-ASR-0.6B"
        case .dualEngine:
            return ""
        }
    }

    /// 是否需要外部标点模型（Qwen3-ASR 自带标点）
    var needsPunctuation: Bool {
        switch self {
        case .qwenASR, .dualEngine:
            return false
        case .streamingParaformer:
            return true
        }
    }

    var modelSize: String {
        switch self {
        case .streamingParaformer:
            return "~216MB"
        case .qwenASR:
            return "~834MB"
        case .dualEngine:
            return "~2.1GB"
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
        case (_, .dualEngine):
            fatalError("dualEngine should not be downloaded directly")
        }
    }

    var displayName: String {
        switch self {
        case .modelScope: return "ModelScope"
        case .github: return "GitHub"
        }
    }
}

/// 模型管理器（编排层）
///
/// 作为 ModelPathResolver / ModelDownloader / ModelExtractionService 的统一入口，
/// 对外保持原有 API 不变，内部委托给专职组件。
class SherpaOnnxManager: NSObject {
    static let shared = SherpaOnnxManager()

    /// 路径解析
    private let pathResolver = ModelPathResolver()
    /// 下载管理
    private let downloader = ModelDownloader()
    /// 解压服务
    private let extractionService = ModelExtractionService()

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

    // MARK: - Streaming Paraformer 模型路径

    /// FP16 模型目录名（原生 ORT 推理使用）
    static let streamingParaformerFP16Folder = "sherpa-onnx-streaming-paraformer-bilingual-zh-en-fp16"

    override init() {
        super.init()
        // 注入解压处理器：下载完成后使用 extractionService 解压到 modelsDirectory
        downloader.extractionHandler = { [weak self] sourceURL, _ in
            guard let self = self else { return false }
            return self.extractionService.extractTarBz2(from: sourceURL, to: self.pathResolver.modelsDirectory)
        }
    }

    // MARK: - Path Resolution (delegate to ModelPathResolver)

    func getStreamingParaformerPath() -> (encoderPath: String, decoderPath: String, tokensPath: String)? {
        pathResolver.getStreamingParaformerPath()
    }

    func isStreamingParaformerDownloaded() -> Bool {
        pathResolver.isStreamingParaformerDownloaded()
    }

    func getQwenASRModelDir() -> String? {
        pathResolver.getQwenASRModelDir()
    }

    func isQwenASRModelDownloaded() -> Bool {
        pathResolver.isQwenASRModelDownloaded()
    }

    func isModelDownloaded(_ modelType: ASRModelType) -> Bool {
        pathResolver.isModelDownloaded(modelType)
    }

    func getPunctuationModelPath() -> String? {
        pathResolver.getPunctuationModelPath()
    }

    func isPunctuationModelDownloaded() -> Bool {
        pathResolver.isPunctuationModelDownloaded()
    }

    func getITNFstPath() -> String? {
        pathResolver.getITNFstPath()
    }

    func isITNFstDownloaded() -> Bool {
        pathResolver.isITNFstDownloaded()
    }

    func getCSCModelPath() -> (modelPath: String, vocabPath: String)? {
        pathResolver.getCSCModelPath()
    }

    func isCSCModelDownloaded() -> Bool {
        pathResolver.isCSCModelDownloaded()
    }

    // MARK: - Download (delegate to ModelDownloader)

    func downloadModel(_ modelType: ASRModelType, progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        downloader.downloadModel(modelType, progress: progress, completion: completion)
    }

    func downloadPunctuationModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isPunctuationModelDownloaded() {
            completion(true, nil)
            return
        }

        Task {
            await MainActor.run {
                progress("正在检测最佳下载源...")
            }

            let primarySource = await downloader.selectFastestPunctSource()
            let fallbackSource: DownloadSource = primarySource == .modelScope ? .github : .modelScope

            await MainActor.run {
                self.downloader.downloadPunctFromSource(
                    source: primarySource,
                    fallback: fallbackSource,
                    destDir: self.pathResolver.modelsDirectory,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    func downloadITNFst(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isITNFstDownloaded() {
            completion(true, nil)
            return
        }

        let itnDir = pathResolver.modelsDirectory.appendingPathComponent(Self.itnWfstFolder)
        downloader.downloadITNFst(destDir: itnDir, progress: progress, completion: completion)
    }

    func downloadCSCModel(progress: @escaping (String) -> Void, completion: @escaping (Bool, String?) -> Void) {
        if isCSCModelDownloaded() {
            completion(true, nil)
            return
        }

        let cscDir = pathResolver.modelsDirectory.appendingPathComponent(Self.cscModelFolder)
        downloader.downloadCSCModel(destDir: cscDir, progress: progress, completion: completion)
    }
}
