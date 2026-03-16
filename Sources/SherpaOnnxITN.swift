import Foundation
import os
#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "SherpaOnnxITN")

/// Sherpa-ONNX 独立逆文本规范化（Inverse Text Normalization）处理器
///
/// 使用 WeTextProcessing WFST 规则将中文数字读法转换为阿拉伯数字等标准格式。
/// 例如：「幺九二点幺六八」→「192.168」
class SherpaOnnxITN {
    private var itn: OpaquePointer?

    /// 初始化 ITN 处理器
    /// - Parameter ruleFsts: 逗号分隔的 FST 文件路径，如 "tagger.fst,verbalizer.fst"
    init?(ruleFsts: String) {
        logger.info("SherpaOnnxITN: 开始初始化...")
        logger.debug("FST 路径: \(ruleFsts, privacy: .public)")

        guard !ruleFsts.isEmpty else {
            logger.info("SherpaOnnxITN: FST 路径为空")
            return nil
        }

        itn = SherpaOnnxCreateInverseTextNormalization(ruleFsts, nil)

        if itn == nil {
            logger.info("SherpaOnnxITN: 创建 ITN 处理器失败")
            return nil
        }

        logger.info("SherpaOnnxITN: 初始化成功")
    }

    deinit {
        if let itn = itn {
            SherpaOnnxDestroyInverseTextNormalization(itn)
        }
    }

    /// 对文本应用逆文本规范化
    func normalize(text: String) -> String {
        guard let itn = itn else { return text }
        guard !text.isEmpty else { return text }

        guard let result = SherpaOnnxInverseTextNormalizationNormalize(itn, text) else {
            return text
        }

        defer { SherpaOnnxInverseTextNormalizationFreeText(result) }

        return String(cString: result)
    }
}
