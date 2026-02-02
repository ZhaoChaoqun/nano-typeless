import SwiftUI

/// 模型下载管理器
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    @Published var isDownloaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: String = ""

    init() {
        checkModelExists()
    }

    func checkModelExists() {
        isDownloaded = SherpaOnnxManager.shared.isModelDownloaded()
    }

    private func notifyDownloadProgress(_ progress: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ModelDownloadProgress"),
            object: nil,
            userInfo: ["progress": progress]
        )
    }

    func downloadModel() {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = "正在下载..."
        notifyDownloadProgress(downloadProgress)

        SherpaOnnxManager.shared.downloadModel(progress: { [weak self] progressText in
            DispatchQueue.main.async {
                self?.downloadProgress = progressText
                self?.notifyDownloadProgress(progressText)
            }
        }, completion: { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isDownloaded = true
                    self?.downloadProgress = "下载完成"
                    self?.notifyDownloadProgress("下载完成")
                    RecordingManager.shared.reloadModel()
                } else {
                    self?.downloadProgress = error ?? "下载失败"
                }
                self?.isDownloading = false
            }
        })
    }
}

/// 设置视图
struct SettingsView: View {
    @StateObject private var downloadManager = ModelDownloadManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SenseVoice FunASR Nano")
                            .fontWeight(.medium)
                        Text("中英文混合识别，支持方言")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if downloadManager.isDownloaded {
                        Label("已下载", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if downloadManager.isDownloading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("下载") {
                            downloadManager.downloadModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                if downloadManager.isDownloading {
                    Text(downloadManager.downloadProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("语音识别模型")
            } footer: {
                Text("模型大小约 179MB，首次使用需要下载。")
            }

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
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
    }
}

#Preview {
    SettingsView()
}
