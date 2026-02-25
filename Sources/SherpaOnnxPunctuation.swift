import Foundation
import os
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxPunctuation")

/// Sherpa-ONNX 离线标点处理器（CT-Transformer）
class SherpaOnnxPunctuation {
    private var punctuator: OpaquePointer?
    private let cStrings = CStringLifetime()

    /// 初始化标点处理器
    init?(modelPath: String) {
        logger.info("SherpaOnnxPunctuation: 开始初始化...")
        logger.debug("模型路径: \(modelPath)")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            logger.info("SherpaOnnxPunctuation: 模型文件不存在")
            return nil
        }

        var config = SherpaOnnxOfflinePunctuationConfig()
        config.model.ct_transformer = cStrings.makeCString(modelPath)
        config.model.num_threads = 2
        config.model.debug = 0
        config.model.provider = cStrings.makeCString("cpu")

        punctuator = SherpaOnnxCreateOfflinePunctuation(&config)

        if punctuator == nil {
            logger.info("SherpaOnnxPunctuation: 创建标点处理器失败")
            return nil
        }

        logger.info("SherpaOnnxPunctuation: 初始化成功")
    }

    deinit {
        if let punctuator = punctuator {
            SherpaOnnxDestroyOfflinePunctuation(punctuator)
        }
    }

    /// 为文本添加标点
    func addPunctuation(text: String) -> String {
        guard let punctuator = punctuator else { return text }
        guard !text.isEmpty else { return text }

        guard let result = SherpaOfflinePunctuationAddPunct(punctuator, text) else {
            return text
        }

        defer { SherpaOfflinePunctuationFreeText(result) }

        return String(cString: result)
    }
}
