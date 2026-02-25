import SwiftUI
import AppKit

/// 悬浮窗口的显示状态
enum OverlayState: Equatable {
    case listening
    case processing
}

/// 悬浮窗口控制器 - 显示录音状态
class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private var viewModel = OverlayViewModel()
    private var sizeObserver: NSObjectProtocol?

    init() {
        setupWindow()
    }

    private func setupWindow() {
        let contentView = OverlayView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)

        // 创建一个无边框的悬浮窗口
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = window else { return }

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        window.hasShadow = true

        // 监听窗口大小变化，保持居中
        sizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hostingView,
            queue: .main
        ) { [weak self] _ in
            self?.centerWindow()
        }
        hostingView?.postsFrameChangedNotifications = true

        // 居中显示在屏幕顶部
        positionWindow()
    }

    private func positionWindow() {
        guard let window = window,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame

        // 放在屏幕顶部中央
        let x = screenFrame.midX - window.frame.width / 2
        let y = screenFrame.maxY - window.frame.height - 60 // 距离顶部60点

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 保持窗口水平居中（内容变化时调用）
    private func centerWindow() {
        guard let window = window,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - window.frame.width / 2

        // 只调整 x 位置，保持 y 不变
        window.setFrameOrigin(NSPoint(x: x, y: window.frame.origin.y))
    }

    func show() {
        viewModel.reset()
        viewModel.state = .listening
        viewModel.startAnimation()
        positionWindow()
        window?.orderFront(nil)
    }

    func updateRecognizedText(_ text: String) {
        viewModel.recognizedText = text
    }

    /// 更新实时音频电平（0.0 ~ 1.0）
    func updateAudioLevel(_ level: Float) {
        viewModel.audioLevel = CGFloat(level)
    }

    /// 切换到处理中状态（停止录音后、识别完成前）
    func showProcessing() {
        viewModel.state = .processing
    }

    func hide() {
        viewModel.stopAnimation()
        window?.orderOut(nil)
    }
}

/// 悬浮窗口视图模型
class OverlayViewModel: ObservableObject {
    @Published var animationPhase: CGFloat = 0
    @Published var recognizedText: String = ""
    @Published var state: OverlayState = .listening
    /// 实时音频电平（0.0 ~ 1.0），由 RecordingManager 驱动
    @Published var audioLevel: CGFloat = 0

    private var animationTimer: Timer?

    func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.animationPhase += 0.15
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func reset() {
        recognizedText = ""
        audioLevel = 0
        state = .listening
    }
}

/// 悬浮窗口视图 - 自适应宽度与滚动效果
struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    // 布局常量
    private let maxWidth: CGFloat = 400      // 最大宽度
    private let maxLines: Int = 5            // 最大行数
    private let lineHeight: CGFloat = 20     // 每行高度

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // 状态指示器 - 始终居中
            statusIndicator

            // 识别结果显示
            if !viewModel.recognizedText.isEmpty {
                textContentView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 130, maxWidth: maxWidth)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.75))
        )
        .animation(.easeInOut(duration: 0.15), value: viewModel.animationPhase)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.state {
        case .listening:
            HStack(spacing: 12) {
                // 录音动画 - 竖纹声波（由真实音量驱动）
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: waveHeight(for: index))
                    }
                }
                .frame(width: 30, height: 18)

                Text("正在聆听...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
        case .processing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)

                Text("识别中...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private var textContentView: some View {
        let textHeight = calculateTextHeight(viewModel.recognizedText)
        let displayHeight = min(textHeight, CGFloat(maxLines) * lineHeight)
        let needsScroll = textHeight > displayHeight
        let textWidth = maxWidth - 32  // 文本区域宽度

        if needsScroll {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(viewModel.recognizedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: textWidth - 16, alignment: .leading)
                        .id("bottom")
                }
                .frame(width: textWidth, height: displayHeight)
                .onChange(of: viewModel.recognizedText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        } else {
            Text(viewModel.recognizedText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textWidth, alignment: .leading)
        }
    }

    private func calculateTextHeight(_ text: String) -> CGFloat {
        // 估算文字行数（简化计算）
        let avgCharsPerLine = 25  // 每行大约25个字符
        let lines = max(1, (text.count + avgCharsPerLine - 1) / avgCharsPerLine)
        return CGFloat(lines) * lineHeight
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let phase = viewModel.animationPhase + CGFloat(index) * 0.6
        // 基础高度 + 音量驱动的动态幅度
        let baseHeight: CGFloat = 4
        // 使用 audioLevel 驱动主幅度，sin(phase) 添加视觉错落
        let level = viewModel.audioLevel
        let dynamicAmplitude: CGFloat = 12 * level
        let jitter = abs(sin(phase)) * (2 + 4 * level)
        return baseHeight + dynamicAmplitude + jitter
    }
}
