import SwiftUI

/// ASR 引擎选择与模型状态视图
struct SettingsASRView: View {
    @ObservedObject var downloadManager: ModelDownloadManager

    var body: some View {
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

            // 标点模型状态（Streaming Paraformer 需要外部标点）
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
            Text("Streaming Paraformer 约 216MB + 标点模型 62MB，Qwen3-ASR 约 834MB（INT8，自带标点），双引擎约 2.1GB。")
        }
    }

    @ViewBuilder
    private func modelStatusView(for model: ASRModelType) -> some View {
        if model == .dualEngine {
            SettingsDualEngineStatusView(downloadManager: downloadManager)
        } else {
            let isDownloaded: Bool = {
                switch model {
                case .streamingParaformer: return downloadManager.streamingParaformerDownloaded
                case .qwenASR: return downloadManager.qwenASRDownloaded
                case .dualEngine: return false
                }
            }()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .fontWeight(.medium)
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
