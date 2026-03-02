import Foundation

/// 流式 ASR 识别器的通用接口
/// 用于在测试中注入 Mock，避免加载真实模型
protocol ASRStreamRecognizing: AnyObject {
    /// 推送新音频并获取增量文本
    func pushAudio(samples: [Float], finalize: Bool) -> String?
    /// 获取当前累积的完整识别结果
    func getResult() -> String
    /// 获取当前已解码但尚未稳定的投机文本
    func getUnfixed() -> String?
    /// 重置流式状态，开始新一轮识别
    func reset()
}
