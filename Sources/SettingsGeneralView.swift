import SwiftUI

/// 通用设置视图（快捷键、关于、权限、数据分析）
struct SettingsGeneralView: View {
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true

    var body: some View {
        Section("快捷键") {
            Text("长按 Fn 键开始录音")
                .foregroundColor(.secondary)
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
