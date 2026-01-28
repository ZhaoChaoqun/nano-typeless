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
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 44),
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
        viewModel.state = .recording
        viewModel.startAnimation()
        positionWindow()
        window?.orderFront(nil)
    }

    func showProcessing() {
        viewModel.state = .processing
        positionWindow()
    }

    func hide() {
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
}

/// 悬浮窗口视图 - 类似截图中的样式
struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 4) {
            if viewModel.state == .recording {
                // 录音动画 - 5个跳动的点
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .offset(y: waveOffset(for: index))
                }
            } else {
                // 处理中 - 显示旋转指示器
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
        }
        .frame(width: 80, height: 20) // 固定内容区域大小，防止切换时窗口跳动
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .animation(.easeInOut(duration: 0.15), value: viewModel.animationPhase)
    }

    private func waveOffset(for index: Int) -> CGFloat {
        let phase = viewModel.animationPhase + CGFloat(index) * 0.5
        return sin(phase) * 6
    }
}
