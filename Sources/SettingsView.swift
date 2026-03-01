import SwiftUI

/// 模型下载管理器
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    @Published var selectedModel: ASRModelType
    @Published var funasrDownloaded: Bool = false
    @Published var streamingParaformerDownloaded: Bool = false
    @Published var qwenASRDownloaded: Bool = false
    @Published var punctuationDownloaded: Bool = false
    @Published var cscDownloaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: String = ""
    @Published var isPunctuationDownloading: Bool = false
    @Published var punctuationDownloadProgress: String = ""
    @Published var isCSCDownloading: Bool = false
    @Published var cscDownloadProgress: String = ""

    init() {
        // 从 UserDefaults 读取选择的模型
        if let rawValue = UserDefaults.standard.string(forKey: "selectedASRModel"),
           let model = ASRModelType(rawValue: rawValue) {
            selectedModel = model
        } else {
            selectedModel = .streamingParaformer
        }
        checkModelsExist()
    }

    func checkModelsExist() {
        funasrDownloaded = SherpaOnnxManager.shared.isFunASRModelDownloaded()
        streamingParaformerDownloaded = SherpaOnnxManager.shared.isStreamingParaformerDownloaded()
        qwenASRDownloaded = SherpaOnnxManager.shared.isQwenASRModelDownloaded()
        punctuationDownloaded = SherpaOnnxManager.shared.isPunctuationModelDownloaded()
        cscDownloaded = SherpaOnnxManager.shared.isCSCModelDownloaded()
    }

    /// 兼容旧接口
    var isDownloaded: Bool {
        switch selectedModel {
        case .funasrNano:
            return funasrDownloaded
        case .streamingParaformer:
            return streamingParaformerDownloaded
        case .qwenASR:
            return qwenASRDownloaded
        }
    }

    private func notifyDownloadProgress(_ progress: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ModelDownloadProgress"),
            object: nil,
            userInfo: ["progress": progress]
        )
    }

    func downloadModel(_ modelType: ASRModelType) {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = "正在下载..."
        notifyDownloadProgress(downloadProgress)

        SherpaOnnxManager.shared.downloadModel(modelType, progress: { [weak self] progressText in
            DispatchQueue.main.async {
                self?.downloadProgress = progressText
                self?.notifyDownloadProgress(progressText)
            }
        }, completion: { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.checkModelsExist()
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

    /// 兼容旧接口
    func downloadModel() {
        downloadModel(selectedModel)
    }

    /// 切换模型
    func switchModel(to model: ASRModelType) {
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "selectedASRModel")
        Task {
            await RecordingManager.shared.switchModel(to: model)
        }
    }

    /// 下载标点模型
    func downloadPunctuationModel() {
        guard !isPunctuationDownloading else { return }

        isPunctuationDownloading = true
        punctuationDownloadProgress = "正在下载标点模型..."

        SherpaOnnxManager.shared.downloadPunctuationModel(progress: { [weak self] progressText in
            DispatchQueue.main.async {
                self?.punctuationDownloadProgress = progressText
            }
        }, completion: { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.punctuationDownloaded = true
                    self?.punctuationDownloadProgress = "下载完成"
                } else {
                    self?.punctuationDownloadProgress = error ?? "下载失败"
                }
                self?.isPunctuationDownloading = false
            }
        })
    }

    /// 下载 CSC 纠错模型
    func downloadCSCModel() {
        guard !isCSCDownloading else { return }

        isCSCDownloading = true
        cscDownloadProgress = "正在下载 CSC 纠错模型..."

        SherpaOnnxManager.shared.downloadCSCModel(progress: { [weak self] progressText in
            DispatchQueue.main.async {
                self?.cscDownloadProgress = progressText
            }
        }, completion: { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.cscDownloaded = true
                    self?.cscDownloadProgress = "下载完成"
                    RecordingManager.shared.reloadModel()
                } else {
                    self?.cscDownloadProgress = error ?? "下载失败"
                }
                self?.isCSCDownloading = false
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
                // 模型选择器
                Picker("识别引擎", selection: Binding(
                    get: { downloadManager.selectedModel },
                    set: { downloadManager.switchModel(to: $0) }
                )) {
                    ForEach(ASRModelType.allCases) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("语音识别模型")
            }

            Section {
                // 当前选中模型的状态
                modelStatusView(for: downloadManager.selectedModel)

                if downloadManager.isDownloading {
                    Text(downloadManager.downloadProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 标点模型状态（仅需要外部标点模型的引擎显示）
                if downloadManager.selectedModel.needsPunctuation {
                    punctuationModelStatusView()

                    if downloadManager.isPunctuationDownloading {
                        Text(downloadManager.punctuationDownloadProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    cscModelStatusView()

                    if downloadManager.isCSCDownloading {
                        Text(downloadManager.cscDownloadProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("模型状态")
            } footer: {
                Text("SenseVoice Nano 约 179MB，Streaming Paraformer 约 216MB + 标点模型 62MB，Qwen3-ASR 约 1.2GB（自带标点）。")
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
        .frame(width: 420, height: 520)
    }

    @ViewBuilder
    private func modelStatusView(for model: ASRModelType) -> some View {
        let isDownloaded: Bool = {
            switch model {
            case .funasrNano: return downloadManager.funasrDownloaded
            case .streamingParaformer: return downloadManager.streamingParaformerDownloaded
            case .qwenASR: return downloadManager.qwenASRDownloaded
            }
        }()

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .fontWeight(.medium)
                if model.needsVAD {
                    Text("需要额外下载 VAD 模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !model.needsPunctuation {
                    Text("自带标点，无需标点模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isDownloaded {
                Label("已下载", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if downloadManager.isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("下载") {
                    downloadManager.downloadModel(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func punctuationModelStatusView() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CT-Transformer 标点模型")
                    .fontWeight(.medium)
                Text("自动为识别结果添加标点符号")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if downloadManager.punctuationDownloaded {
                Label("已下载", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if downloadManager.isPunctuationDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("下载") {
                    downloadManager.downloadPunctuationModel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func cscModelStatusView() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CSC 中文拼写纠错")
                    .fontWeight(.medium)
                Text("自动纠正 ASR 中的同音字错误（98MB）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if downloadManager.cscDownloaded {
                Label("已下载", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if downloadManager.isCSCDownloading {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView()
                        .scaleEffect(0.7)
                    if !downloadManager.cscDownloadProgress.isEmpty {
                        Text(downloadManager.cscDownloadProgress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button("下载") {
                    downloadManager.downloadCSCModel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

#Preview {
    SettingsView()
}
