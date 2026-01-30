import SwiftUI
import AppKit

/// 首次启动引导状态
enum OnboardingState {
    case downloading(progress: String)  // 正在下载模型
    case loading                         // 模型加载中
    case ready                           // 准备就绪，可以使用
}

/// 引导界面视图模型
class OnboardingViewModel: ObservableObject {
    @Published var state: OnboardingState = .downloading(progress: "正在准备...")
    @Published var isVisible: Bool = false

    private var downloadObserver: NSObjectProtocol?
    private var autoDismissTimer: Timer?

    init() {
        setupObservers()
    }

    deinit {
        if let observer = downloadObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        autoDismissTimer?.invalidate()
    }

    private func setupObservers() {
        // 监听模型下载进度
        downloadObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModelDownloadProgress"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let progress = notification.userInfo?["progress"] as? String {
                self?.state = .downloading(progress: progress)
            }
        }
    }

    func checkModelStatus() {
        let downloadManager = ModelDownloadManager.shared
        let hasAnyModel = downloadManager.availableModels.contains { downloadManager.isModelDownloaded($0.id) }

        if hasAnyModel {
            // 有模型，检查是否已加载
            if RecordingManager.shared.isInitialized {
                state = .ready
                startAutoDismissTimer()
            } else {
                state = .loading
                // 轮询检查模型加载状态
                pollModelLoadingStatus()
            }
        } else {
            // 无模型，等待下载
            state = .downloading(progress: "正在下载语音识别模型...")
            pollDownloadStatus()
        }
    }

    private func pollDownloadStatus() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let downloadManager = ModelDownloadManager.shared

            // 更新下载进度
            if downloadManager.downloadingModel != nil {
                self.state = .downloading(progress: downloadManager.downloadProgress)
            }

            // 检查是否已有模型下载完成
            let hasAnyModel = downloadManager.availableModels.contains { downloadManager.isModelDownloaded($0.id) }
            if hasAnyModel {
                timer.invalidate()
                self.state = .loading
                self.pollModelLoadingStatus()
            }
        }
    }

    private func pollModelLoadingStatus() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if RecordingManager.shared.isInitialized {
                timer.invalidate()
                self.state = .ready
                self.startAutoDismissTimer()
            }
        }
    }

    /// 就绪状态后自动关闭
    private func startAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.isVisible = false
        }
    }
}

/// 引导气泡窗口控制器
class OnboardingWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OnboardingBubbleView>?
    private var viewModel = OnboardingViewModel()
    private var statusItemFrame: NSRect = .zero

    private let hasShownOnboardingKey = "hasShownOnboarding"

    init() {
        setupObservers()
    }

    private func setupObservers() {
        // 监听 viewModel 的 isVisible 变化
        // 使用 KVO 或直接在 show/dismiss 中控制
    }

    private func setupWindow() {
        let contentView = OnboardingBubbleView(viewModel: viewModel) { [weak self] in
            self?.dismiss()
        }
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = NSRect(x: 0, y: 0, width: 280, height: 100)

        // 创建小气泡窗口
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
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
        window.hasShadow = true
    }

    /// 是否需要显示引导
    var shouldShowOnboarding: Bool {
        return !UserDefaults.standard.bool(forKey: hasShownOnboardingKey)
    }

    /// 设置菜单栏图标位置（用于定位气泡）
    func setStatusItemFrame(_ frame: NSRect) {
        self.statusItemFrame = frame
    }

    /// 显示引导气泡
    func show() {
        guard shouldShowOnboarding else { return }

        setupWindow()

        viewModel.isVisible = true
        viewModel.checkModelStatus()

        // 监听 isVisible 变化来自动关闭
        observeVisibility()

        positionWindow()
        window?.orderFront(nil)
    }

    /// 监听 isVisible 变化
    private var visibilityObserver: NSKeyValueObservation?
    private var cancellable: Any?

    private func observeVisibility() {
        // 使用 Timer 轮询检查 isVisible 状态
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if !self.viewModel.isVisible {
                timer.invalidate()
                self.dismiss()
            }
        }
    }

    /// 定位窗口到菜单栏下方
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        let windowSize = window.frame.size
        let screenFrame = screen.frame

        // 如果有菜单栏图标位置，定位到图标下方
        if statusItemFrame != .zero {
            let x = statusItemFrame.midX - windowSize.width / 2
            let y = screenFrame.maxY - statusItemFrame.height - windowSize.height - 8
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // 否则定位到屏幕右上角菜单栏下方
            let x = screenFrame.maxX - windowSize.width - 20
            let y = screenFrame.maxY - 30 - windowSize.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// 关闭引导气泡
    func dismiss() {
        viewModel.isVisible = false
        window?.orderOut(nil)

        // 标记已显示过引导
        UserDefaults.standard.set(true, forKey: hasShownOnboardingKey)
    }

    /// 重置引导状态（用于测试）
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: hasShownOnboardingKey)
    }
}

/// 引导气泡视图
struct OnboardingBubbleView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 小三角箭头
            Triangle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: 16, height: 8)

            // 主内容
            HStack(spacing: 12) {
                // 左侧图标
                iconView
                    .frame(width: 36, height: 36)

                // 右侧文字
                VStack(alignment: .leading, spacing: 4) {
                    mainText
                    subtitleText
                }

                Spacer()

                // 关闭按钮
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private var iconView: some View {
        switch viewModel.state {
        case .downloading:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
        case .loading:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)
        }
    }

    @ViewBuilder
    private var mainText: some View {
        switch viewModel.state {
        case .downloading:
            Text("正在下载模型")
                .font(.system(size: 13, weight: .medium))
        case .loading:
            Text("正在加载模型")
                .font(.system(size: 13, weight: .medium))
        case .ready:
            Text("长按 Fn 键开始说话")
                .font(.system(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        switch viewModel.state {
        case .downloading(let progress):
            Text(progress)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        case .loading:
            Text("首次加载需要一点时间...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .ready:
            Text("松开即可输入识别的文字")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

/// 小三角形状
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
