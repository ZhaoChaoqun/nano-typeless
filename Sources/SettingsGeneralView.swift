import SwiftUI

/// 通用设置视图（快捷键、关于、权限）
struct SettingsGeneralView: View {
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
    }
}
