import SwiftUI

/// 双引擎模式状态视图
struct SettingsDualEngineStatusView: View {
    @ObservedObject var downloadManager: ModelDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("双引擎模式")
                .fontWeight(.medium)
            Text("Paraformer 实时预览 + Qwen3-ASR 精转写，自带标点")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Streaming Paraformer")
                    .font(.caption)
                Spacer()
                if downloadManager.streamingParaformerDownloaded {
                    Label("已下载", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if downloadManager.isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("下载") {
                        downloadManager.downloadModel(.streamingParaformer)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            HStack {
                Text("Qwen3-ASR")
                    .font(.caption)
                Spacer()
                if downloadManager.qwenASRDownloaded {
                    Label("已下载", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if downloadManager.isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("下载") {
                        downloadManager.downloadModel(.qwenASR)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
    }
}
