import SwiftUI

/// 通用设置视图（快捷键、关于、权限、数据分析）
struct SettingsGeneralView: View {
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true

    /// 当前触发键的显示名称（从 TriggerKeyConfig 读取）
    @State private var triggerKeyName: String = TriggerKeyConfig.current.displayName
    /// 是否处于按键录制状态
    @State private var isRecording = false

    var body: some View {
        Section {
            HStack {
                Text("触发键")
                Spacer()
                if isRecording {
                    Text("请按下任意键...")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(triggerKeyName)
                        .foregroundStyle(.secondary)
                }
                Button(isRecording ? "取消" : "录制按键") {
                    if isRecording {
                        // 取消录制
                        isRecording = false
                        NotificationCenter.default.post(
                            name: .triggerKeyRecordingCancelled, object: nil)
                    } else {
                        // 开始录制
                        isRecording = true
                        NotificationCenter.default.post(
                            name: .triggerKeyRecordingRequested, object: nil)
                    }
                }
                .buttonStyle(.bordered)
            }
            if triggerKeyName != TriggerKeyConfig.defaultFn.displayName {
                Button("恢复默认 (Fn)") {
                    TriggerKeyConfig.defaultFn.save()
                    triggerKeyName = TriggerKeyConfig.defaultFn.displayName
                    NotificationCenter.default.post(name: .triggerKeyChanged, object: nil)
                }
            }
        } header: {
            Text("快捷键")
        } footer: {
            Text("长按所选按键开始录音，松开结束。外接机械键盘的 Fn 键通常无法被系统检测，建议录制其他按键。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerKeyRecorded)) { notification in
            if let config = notification.object as? TriggerKeyConfig {
                triggerKeyName = config.displayName
                isRecording = false
            }
        }

        Section("关于") {
            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
            LabeledContent("作者", value: "赵超群（Zhao Chaoqun）")
        }

        Section {
            Link("辅助功能设置", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            Link("麦克风设置", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        } header: {
            Text("权限")
        } footer: {
            Text("Nano Typeless 需要辅助功能权限来监听全局按键，需要麦克风权限来录制语音。")
        }

        Section {
            Toggle("发送匿名使用统计", isOn: $analyticsEnabled)
        } header: {
            Text("数据分析")
        } footer: {
            Text("帮助改进 Nano Typeless。不会收集任何文本内容或个人信息。")
        }
        .onChange(of: analyticsEnabled) { _, newValue in
            AnalyticsService.setEnabled(newValue)
        }
    }
}
