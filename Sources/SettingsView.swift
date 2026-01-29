import SwiftUI
import WhisperKit

/// 语音识别引擎类型
enum SpeechEngine: String, CaseIterable {
    case funasr = "FunASR"
    case whisper = "Whisper"

    var displayName: String {
        switch self {
        case .funasr: return "FunASR (阿里)"
        case .whisper: return "Whisper (OpenAI)"
        }
    }
}

/// 模型信息
struct SpeechModel: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let size: String
    let engine: SpeechEngine
}

/// 旧的 WhisperModel 类型别名，保持兼容
typealias WhisperModel = SpeechModel

/// 模型下载管理器
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    /// FunASR 模型
    let funasrModels: [SpeechModel] = [
        SpeechModel(id: "paraformer", name: "paraformer-zh", displayName: "Paraformer", description: "推荐使用，中文识别效果最佳", size: "~220MB", engine: .funasr),
        SpeechModel(id: "sensevoice-small", name: "SenseVoiceSmall", displayName: "SenseVoice Small", description: "多语言支持，情感识别", size: "~450MB", engine: .funasr)
    ]

    /// Whisper 模型
    let whisperModels: [SpeechModel] = [
        SpeechModel(id: "tiny", name: "tiny", displayName: "Tiny", description: "最快速度，适合简单短句", size: "~40MB", engine: .whisper),
        SpeechModel(id: "base", name: "base", displayName: "Base", description: "速度与准确性平衡", size: "~140MB", engine: .whisper),
        SpeechModel(id: "small", name: "small", displayName: "Small", description: "更高准确性，速度稍慢", size: "~460MB", engine: .whisper),
        SpeechModel(id: "large-v3_turbo", name: "large-v3_turbo", displayName: "Large V3 Turbo", description: "最高准确性，中英混合识别最佳", size: "~1.5GB", engine: .whisper)
    ]

    /// 所有可用模型
    var availableModels: [SpeechModel] {
        return funasrModels + whisperModels
    }

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
    private func modelFolder(for model: SpeechModel) -> URL {
        if model.engine == .funasr {
            return SherpaOnnxManager.shared.getModelDirectory(for: model.id)
        } else {
            // 使用 Application Support 目录，避免触发文稿文件夹访问弹窗
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Typeless/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(model.name)")
        }
    }

    /// 检查所有模型是否已下载
    func checkAllModelsExist() {
        var downloaded = Set<String>()

        // 检查 FunASR 模型
        for model in funasrModels {
            if SherpaOnnxManager.shared.isModelDownloaded(model.id) {
                downloaded.insert(model.id)
            }
        }

        // 检查 Whisper 模型
        for model in whisperModels {
            let folder = modelFolder(for: model)
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

        if model.engine == .funasr {
            // 使用 Sherpa-ONNX 下载 FunASR 模型
            SherpaOnnxManager.shared.downloadModel(modelId, progress: { [weak self] progressText in
                DispatchQueue.main.async {
                    self?.downloadProgress = progressText
                }
            }, completion: { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.downloadedModels.insert(modelId)
                        self?.downloadProgress = "下载完成"
                    } else {
                        self?.downloadProgress = error ?? "下载失败"
                    }
                    self?.downloadingModel = nil
                }
            })
        } else {
            // 使用 WhisperKit 下载 Whisper 模型
            // 使用 Application Support 目录，避免触发文稿文件夹访问弹窗
            let whisperModelRepo = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Typeless/huggingface/models/argmaxinc/whisperkit-coreml")
            try? FileManager.default.createDirectory(at: whisperModelRepo, withIntermediateDirectories: true)

            Task {
                do {
                    let _ = try await WhisperKit(
                        model: model.name,
                        modelFolder: whisperModelRepo.path,
                        verbose: true,
                        logLevel: .debug,
                        prewarm: false,
                        load: false,
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
    @AppStorage("modelSize") private var modelSize = "paraformer"
    @StateObject private var downloadManager = ModelDownloadManager.shared

    init() {
        print(">>> SettingsView init() 被调用")
    }

    var body: some View {
        let _ = print(">>> SettingsView body 被计算")
        Form {
            Section {
                ForEach(downloadManager.funasrModels) { model in
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
                            RecordingManager.shared.switchToModel(model.id)
                        }
                    )
                }
            } header: {
                Text("FunASR 模型（阿里）")
            } footer: {
                Text("FunASR 模型针对中文优化，识别速度快、准确率高。")
            }

            Section {
                ForEach(downloadManager.whisperModels) { model in
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
                            RecordingManager.shared.switchToModel(model.id)
                        }
                    )
                }
            } header: {
                Text("Whisper 模型（OpenAI）")
            } footer: {
                Text("Whisper 模型支持多语言，更大的模型识别更准确，但下载和加载速度更慢。")
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
                Text("Typeless 需要辅助功能权限来监听全局按键，需要麦克风权限来录制语音。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 550)
    }
}

#Preview {
    SettingsView()
}
