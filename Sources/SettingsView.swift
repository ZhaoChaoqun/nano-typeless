import SwiftUI

/// 模型下载管理器
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    @Published var selectedModel: ASRModelType
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
            selectedModel = .qwenASR
        }
        checkModelsExist()
    }

    func checkModelsExist() {
        streamingParaformerDownloaded = SherpaOnnxManager.shared.isStreamingParaformerDownloaded()
        qwenASRDownloaded = SherpaOnnxManager.shared.isQwenASRModelDownloaded()
        punctuationDownloaded = SherpaOnnxManager.shared.isPunctuationModelDownloaded()
        cscDownloaded = SherpaOnnxManager.shared.isCSCModelDownloaded()
    }

    /// 兼容旧接口
    var isDownloaded: Bool {
        switch selectedModel {
        case .streamingParaformer:
            return streamingParaformerDownloaded
        case .qwenASR:
            return qwenASRDownloaded
        case .dualEngine:
            return streamingParaformerDownloaded && qwenASRDownloaded
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
            SettingsASRView(downloadManager: downloadManager)
            SettingsGeneralView()
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 600)
    }
}

#Preview {
    SettingsView()
}
