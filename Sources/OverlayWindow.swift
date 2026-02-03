import SwiftUI
import AppKit

/// 悬浮窗口控制器 - 显示录音状态
class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private var viewModel = OverlayViewModel()

    init() {
        setupWindow()
    }

    private func setupWindow() {
        let contentView = OverlayView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)

        // 创建一个无边框的悬浮窗口
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
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

        // 居中显示在屏幕顶部
        positionWindow()
    }

    private func positionWindow() {
        guard let window = window,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // 放在屏幕顶部中央
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.maxY - windowSize.height - 60 // 距离顶部60点

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        print(">>> OverlayWindow show() called")
        viewModel.state = .recording
        viewModel.reset()
        viewModel.startAnimation()
        positionWindow()
        window?.orderFront(nil)
        print(">>> OverlayWindow window visible: \(window?.isVisible ?? false)")
    }

    func showProcessing() {
        print(">>> OverlayWindow showProcessing() called")
        viewModel.state = .processing
        positionWindow()
    }

    func updateRecognizedText(_ text: String) {
        viewModel.recognizedText = text
        // 窗口内容变化时重新定位
        DispatchQueue.main.async { [weak self] in
            self?.positionWindow()
        }
    }

    func hide() {
        print(">>> OverlayWindow hide() called")
        viewModel.stopAnimation()
        window?.orderOut(nil)
    }
}

/// 悬浮窗口视图模型
class OverlayViewModel: ObservableObject {
    enum State {
        case recording
        case processing
    }

    @Published var state: State = .recording
    @Published var animationPhase: CGFloat = 0
    @Published var recognizedText: String = ""

    private var animationTimer: Timer?

    func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.animationPhase += 0.3
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func reset() {
        recognizedText = ""
    }
}

/// 悬浮窗口视图 - 类似截图中的样式
struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 主状态指示器
            HStack(spacing: 12) {
                // 左侧图标区域 - 固定宽度
                Group {
                    if viewModel.state == .recording {
                        // 录音动画 - 竖纹声波
                        HStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 3, height: waveHeight(for: index))
                            }
                        }
                    } else {
                        // 处理中 - 显示旋转指示器
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    }
                }
                .frame(width: 30, height: 18)

                // 右侧文字区域 - 固定宽度确保一致
                Text(viewModel.state == .recording ? "正在聆听..." : "识别中...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 75, alignment: .leading)
            }

            // 识别结果显示（当有文字时）
            if !viewModel.recognizedText.isEmpty {
                Text(viewModel.recognizedText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: 280)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
        )
        .animation(.easeInOut(duration: 0.1), value: viewModel.animationPhase)
        .animation(.easeInOut(duration: 0.2), value: viewModel.recognizedText)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let phase = viewModel.animationPhase + CGFloat(index) * 0.6
        let baseHeight: CGFloat = 6
        let amplitude: CGFloat = 10
        return baseHeight + abs(sin(phase)) * amplitude
    }
}
