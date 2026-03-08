import Foundation
@testable import Nano_Typeless

/// 测试环境共用工具：模型路径查找、项目根目录定位
enum TestEnvironment {

    /// Qwen3-ASR 模型目录，不存在则返回 nil
    static func qwenModelDirectory() -> String? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Nano Typeless/models/Qwen3-ASR-0.6B")

        if FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("vocab.json").path) {
            return appSupport.path
        }

        if let envDir = ProcessInfo.processInfo.environment["QWEN_MODEL_DIR"],
           FileManager.default.fileExists(atPath: envDir + "/vocab.json") {
            return envDir
        }

        return nil
    }

    /// 模型是否可用（仅检查文件是否存在，不加载模型）
    static var isModelAvailable: Bool {
        qwenModelDirectory() != nil
    }

    /// 项目根目录（通过调用处的 #filePath 推断）
    ///
    /// 使用方式：`TestEnvironment.projectRoot(from: #filePath)`
    /// 假设调用文件位于 `<project_root>/TypelessTests/SomeTest.swift`
    static func projectRoot(from filePath: String = #filePath) -> String {
        if let root = ProcessInfo.processInfo.environment["PROJECT_ROOT"] {
            return root
        }

        let root = ((filePath as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent

        let markers = ["Typeless.xcodeproj", "Package.swift"]
        for marker in markers {
            if FileManager.default.fileExists(atPath: root + "/" + marker) {
                return root
            }
        }

        return FileManager.default.currentDirectoryPath
    }

    /// tests/fixtures 目录路径
    static func fixturesPath(from filePath: String = #filePath) -> String {
        projectRoot(from: filePath) + "/tests/fixtures"
    }

    // MARK: - 模型路径（基于 SherpaOnnxManager）

    /// 模型根目录
    static var modelsDirectory: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nano Typeless/models").path
    }

    /// Streaming Paraformer 模型路径
    static func paraformerPaths() -> (encoder: String, decoder: String, tokens: String)? {
        SherpaOnnxManager.shared.getStreamingParaformerPath().map {
            ($0.encoderPath, $0.decoderPath, $0.tokensPath)
        }
    }

    /// VAD 模型路径
    static func vadModelPath() -> String? {
        SherpaOnnxManager.shared.getVADModelPath()
    }

    /// CT-Transformer 标点模型路径
    static func punctuationModelPath() -> String? {
        SherpaOnnxManager.shared.getPunctuationModelPath()
    }

    /// CSC 纠错模型路径
    static func cscModelPaths() -> (model: String, vocab: String)? {
        SherpaOnnxManager.shared.getCSCModelPath().map {
            ($0.modelPath, $0.vocabPath)
        }
    }

    /// ITN WFST 路径（comma-separated tagger + verbalizer）
    static func itnFstPath() -> String? {
        SherpaOnnxManager.shared.getITNFstPath()
    }

}
