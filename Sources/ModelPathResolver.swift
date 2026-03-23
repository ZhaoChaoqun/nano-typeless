import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "ModelPathResolver")

/// 模型路径解析器
///
/// 负责解析各类模型的本地路径，检查文件是否存在，
/// 返回可用的模型路径。不涉及下载或解压逻辑。
class ModelPathResolver {

    /// 模型存储根目录
    let modelsDirectory: URL = {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models")
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
        return appSupportPath
    }()

    // MARK: - Streaming Paraformer

    /// 获取 Streaming Paraformer 模型路径（优先 FP32，fallback INT8）
    func getStreamingParaformerPath() -> (encoderPath: String, decoderPath: String, tokensPath: String)? {
        let modelDir = modelsDirectory.appendingPathComponent(ASRModelType.streamingParaformer.folderName)
        let tokensPath = modelDir.appendingPathComponent("tokens.txt")

        guard FileManager.default.fileExists(atPath: tokensPath.path) else {
            return nil
        }

        // 优先 FP32
        let encoderFP32 = modelDir.appendingPathComponent("encoder.onnx")
        let decoderFP32 = modelDir.appendingPathComponent("decoder.onnx")

        if FileManager.default.fileExists(atPath: encoderFP32.path),
           FileManager.default.fileExists(atPath: decoderFP32.path) {
            return (encoderFP32.path, decoderFP32.path, tokensPath.path)
        }

        // Fallback INT8
        let encoderINT8 = modelDir.appendingPathComponent("encoder.int8.onnx")
        let decoderINT8 = modelDir.appendingPathComponent("decoder.int8.onnx")

        if FileManager.default.fileExists(atPath: encoderINT8.path),
           FileManager.default.fileExists(atPath: decoderINT8.path) {
            return (encoderINT8.path, decoderINT8.path, tokensPath.path)
        }

        return nil
    }

    /// 检查 Streaming Paraformer 模型是否已下载
    func isStreamingParaformerDownloaded() -> Bool {
        return getStreamingParaformerPath() != nil
    }

    // MARK: - QwenASR

    /// 获取 QwenASR 模型目录路径
    func getQwenASRModelDir() -> String? {
        let modelDir = modelsDirectory.appendingPathComponent(ASRModelType.qwenASR.folderName)

        // 检查关键文件：vocab.json 必须存在
        let vocabPath = modelDir.appendingPathComponent("vocab.json")
        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            return nil
        }

        // 检查模型权重文件（三种格式任一即可）
        // 1. INT8 量化模型
        let qint8Path = modelDir.appendingPathComponent("model_int8.qint8")
        if FileManager.default.fileExists(atPath: qint8Path.path) {
            return modelDir.path
        }

        // 2. 单文件 safetensors
        let singlePath = modelDir.appendingPathComponent("model.safetensors")
        if FileManager.default.fileExists(atPath: singlePath.path) {
            return modelDir.path
        }

        // 3. 分片模型：检查 model-00001-of-*.safetensors
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
        case .dualEngine:
            return isStreamingParaformerDownloaded() && isQwenASRModelDownloaded()
        }
    }

    // MARK: - 标点模型

    /// 获取标点模型路径
    func getPunctuationModelPath() -> String? {
        let modelDir = modelsDirectory.appendingPathComponent(SherpaOnnxManager.punctModelFolder)
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

    // MARK: - ITN WFST 模型

    /// 获取 ITN WFST 路径（逗号分隔的 tagger + verbalizer 路径，供 sherpa-onnx rule_fsts 使用）
    func getITNFstPath() -> String? {
        let itnDir = modelsDirectory.appendingPathComponent(SherpaOnnxManager.itnWfstFolder)
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

    // MARK: - CSC 模型

    /// 获取 CSC 模型路径
    func getCSCModelPath() -> (modelPath: String, vocabPath: String)? {
        let modelDir = modelsDirectory.appendingPathComponent(SherpaOnnxManager.cscModelFolder)
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
}
