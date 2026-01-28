import SwiftUI
import WhisperKit

/// 模型信息
struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let size: String
}

/// 模型下载管理器
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    /// 所有可用模型
    let availableModels: [WhisperModel] = [
        WhisperModel(id: "tiny", name: "tiny", displayName: "Tiny", description: "最快速度，适合简单短句", size: "~40MB"),
        WhisperModel(id: "base", name: "base", displayName: "Base", description: "推荐日常使用，速度与准确性平衡", size: "~140MB"),
        WhisperModel(id: "small", name: "small", displayName: "Small", description: "更高准确性，速度稍慢", size: "~460MB"),
        WhisperModel(id: "large-v3_turbo", name: "large-v3_turbo", displayName: "Large V3 Turbo", description: "最高准确性，中英混合识别最佳", size: "~1.5GB")
    ]

    /// 各模型的下载状态
    @Published var downloadedModels: Set<String> = []
    /// 当前正在下载的模型
    @Published var downloadingModel: String? = nil
    /// 下载进度信息
    @Published var downloadProgress: String = ""

    init() {
        checkAllModelsExist()
    }

    /// 获取模型文件夹路径
    private func modelFolder(for modelName: String) -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
    }

    /// 检查所有模型是否已下载
    func checkAllModelsExist() {
        var downloaded = Set<String>()
        for model in availableModels {
            let folder = modelFolder(for: model.name)
            let configPath = folder.appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: configPath.path) {
                downloaded.insert(model.id)
            }
        }
        downloadedModels = downloaded
    }

    /// 检查指定模型是否已下载
    func isModelDownloaded(_ modelId: String) -> Bool {
        return downloadedModels.contains(modelId)
    }

    /// 检查指定模型是否正在下载
    func isDownloading(_ modelId: String) -> Bool {
        return downloadingModel == modelId
    }

    /// 下载指定模型
    func downloadModel(_ modelId: String) {
        guard downloadingModel == nil else { return }
        guard let model = availableModels.first(where: { $0.id == modelId }) else { return }

        downloadingModel = modelId
        downloadProgress = "正在下载 \(model.displayName) 模型..."

        Task {
            do {
                // 使用 WhisperKit 下载模型
                let _ = try await WhisperKit(
                    model: model.name,
                    verbose: true,
                    logLevel: .debug,
                    prewarm: false,
                    load: false,  // 只下载，不加载
                    download: true
                )

                await MainActor.run {
                    self.downloadedModels.insert(modelId)
                    self.downloadingModel = nil
                    self.downloadProgress = "下载完成"
                }
            } catch {
                await MainActor.run {
                    self.downloadingModel = nil
                    self.downloadProgress = "下载失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// 单个模型的行视图
struct ModelRowView: View {
    let model: WhisperModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let isSelected: Bool
    let downloadProgress: String
    let onDownload: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .fontWeight(.medium)
                        Text(model.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isDownloaded {
                    if isSelected {
                        Label("使用中", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Button("切换") {
                            onSelect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("下载") {
                        onDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if isDownloading {
                Text(downloadProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 设置视图
struct SettingsView: View {
    @AppStorage("triggerKey") private var triggerKey = "fn"
    @AppStorage("modelSize") private var modelSize = "base"
    @StateObject private var downloadManager = ModelDownloadManager.shared

    init() {
        print(">>> SettingsView init() 被调用")
    }

    var body: some View {
        let _ = print(">>> SettingsView body 被计算")
        Form {
            Section {
                ForEach(downloadManager.availableModels) { model in
                    ModelRowView(
                        model: model,
                        isDownloaded: downloadManager.isModelDownloaded(model.id),
                        isDownloading: downloadManager.isDownloading(model.id),
                        isSelected: modelSize == model.id,
                        downloadProgress: downloadManager.downloadProgress,
                        onDownload: {
                            downloadManager.downloadModel(model.id)
                        },
                        onSelect: {
                            modelSize = model.id
                        }
                    )
                    if model.id != downloadManager.availableModels.last?.id {
                        Divider()
                    }
                }
            } header: {
                Text("Whisper 模型")
            } footer: {
                Text("更大的模型识别更准确，但下载和加载速度更慢。首次使用需要先下载模型。")
            }

            Section("快捷键") {
                Text("长按 Fn 键开始录音")
                    .foregroundColor(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("作者", value: "Typeless Team")
            }

            Section {
                Link("辅助功能设置", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                Link("麦克风设置", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            } header: {
                Text("权限")
            } footer: {
                Text("Typeless 需要辅助功能权限来监听全局按键，需要麦克风权限来录制语音。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }
}

#Preview {
    SettingsView()
}
