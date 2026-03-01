import SwiftUI
import AppKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "TypelessApp")

@main
struct TypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var overlayWindow: OverlayWindowController?
    var onboardingWindow: OnboardingWindowController?
    var keyMonitor: KeyMonitor?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()

        _ = RecordingManager.shared
        overlayWindow = OverlayWindowController()

        // 一次性注册所有回调
        setupRecordingCallbacks()

        keyMonitor = KeyMonitor()
        keyMonitor?.onKeyDown = {
            RecordingManager.shared.handleEvent(.fnKeyDown)
        }
        keyMonitor?.onKeyUp = {
            RecordingManager.shared.handleEvent(.fnKeyUp)
        }
        keyMonitor?.startMonitoring()

        checkPermissions()
        autoDownloadDefaultModelIfNeeded()
        showOnboardingIfNeeded()
    }

    private func showOnboardingIfNeeded() {
        onboardingWindow = OnboardingWindowController()
        if onboardingWindow?.shouldShowOnboarding == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let button = self?.statusItem?.button, let buttonWindow = button.window {
                    let frameInScreen = buttonWindow.convertToScreen(button.frame)
                    self?.onboardingWindow?.setStatusItemFrame(frameInScreen)
                }
                self?.onboardingWindow?.show()
            }
        }
    }

    private func autoDownloadDefaultModelIfNeeded() {
        let downloadManager = ModelDownloadManager.shared
        if !downloadManager.isDownloaded {
            logger.info("首次启动，自动下载默认模型...")
            downloadManager.downloadModel()
        }
        if !downloadManager.punctuationDownloaded {
            logger.info("自动下载标点模型...")
            downloadManager.downloadPunctuationModel()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Nano Typeless")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Nano Typeless - 语音输入", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "长按 Fn 键开始录音", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func checkPermissions() {
        // 单元测试环境下跳过权限请求
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // 请求麦克风权限
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async { self.showPermissionAlert(for: "麦克风") }
            }
        }
        // 辅助功能权限已在 KeyMonitor.startMonitoring() 中请求
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "需要\(permission)权限"
        alert.informativeText = "请在系统设置中授予 Nano Typeless \(permission)访问权限"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            if permission == "麦克风" {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }

    private func setupRecordingCallbacks() {
        RecordingManager.shared.onRecordingStarted = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayWindow?.show()
            }
        }

        RecordingManager.shared.onPartialResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.overlayWindow?.updateRecognizedText(text)
            }
        }

        RecordingManager.shared.onAudioLevel = { [weak self] level in
            self?.overlayWindow?.updateAudioLevel(level)
        }

        RecordingManager.shared.onProcessingStarted = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayWindow?.showProcessing()
            }
        }

        RecordingManager.shared.onFinalResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.overlayWindow?.hide()
                if let text = text, !text.isEmpty {
                    TextInserter.insertText(text)
                }
            }
        }
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Nano Typeless 设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 380))
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
