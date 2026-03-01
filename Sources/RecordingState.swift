import Foundation

/// 录音管理器的有限状态
enum RecordingState: Equatable, CustomStringConvertible {
    case idle                                    // 无引擎或引擎未就绪
    case initializing                            // 正在加载模型
    case ready                                   // 等待 Fn 按下
    case recording(accumulatedText: String)       // 录音中
    case flushing(accumulatedText: String)        // 正在刷出最终结果
    case postProcessing(rawText: String)          // CSC + 标点处理

    var description: String {
        switch self {
        case .idle: return "idle"
        case .initializing: return "initializing"
        case .ready: return "ready"
        case .recording: return "recording"
        case .flushing: return "flushing"
        case .postProcessing: return "postProcessing"
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// 纯函数状态转换表
    /// 返回 nil 表示该事件在当前状态下非法/被忽略
    static func nextState(from state: RecordingState, event: RecordingEvent) -> RecordingState? {
        switch (state, event) {
        // 模型加载
        case (.idle, .reloadRequested):
            return .initializing
        case (.idle, .modelLoaded):
            return .ready
        case (.initializing, .modelLoaded):
            return .ready
        case (.initializing, .modelLoadFailed):
            return .idle
        case (.ready, .reloadRequested):
            return .initializing

        // 录音生命周期
        case (.ready, .fnKeyDown):
            return .recording(accumulatedText: "")
        case (.recording, .partialResult(let text)):
            return .recording(accumulatedText: text)
        case (.recording, .audioReceived):
            return state  // 状态不变，仅触发副作用
        case (.recording, .fnKeyUp):
            if case .recording(let accText) = state {
                return .flushing(accumulatedText: accText)
            }
            return nil
        case (.flushing, .flushComplete(let rawText)):
            return .postProcessing(rawText: rawText)
        case (.postProcessing, .postProcessComplete):
            return .ready

        default:
            return nil
        }
    }
}

/// 驱动状态转换的事件
enum RecordingEvent: CustomStringConvertible {
    case modelLoaded
    case modelLoadFailed
    case fnKeyDown
    case fnKeyUp
    case audioReceived(samples: [Float])
    case partialResult(text: String)
    case flushComplete(rawText: String)
    case postProcessComplete(finalText: String?)
    case reloadRequested

    var description: String {
        switch self {
        case .modelLoaded: return "modelLoaded"
        case .modelLoadFailed: return "modelLoadFailed"
        case .fnKeyDown: return "fnKeyDown"
        case .fnKeyUp: return "fnKeyUp"
        case .audioReceived: return "audioReceived"
        case .partialResult: return "partialResult"
        case .flushComplete: return "flushComplete"
        case .postProcessComplete: return "postProcessComplete"
        case .reloadRequested: return "reloadRequested"
        }
    }
}
