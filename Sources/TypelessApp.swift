import SwiftUI
import AppKit
import AVFoundation

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
    var recordingManager: RecordingManager?
    var overlayWindow: OverlayWindowController?
    var keyMonitor: KeyMonitor?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Setup status bar item
        setupStatusBar()

        // Initialize managers
        recordingManager = RecordingManager()
        overlayWindow = OverlayWindowController()

        // Setup key monitoring
        keyMonitor = KeyMonitor()
        keyMonitor?.onKeyDown = { [weak self] in
            self?.startRecording()
        }
        keyMonitor?.onKeyUp = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }
        keyMonitor?.startMonitoring()

        // Check permissions
        checkPermissions()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Typeless")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Typeless - 语音输入", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "长按 Fn 键开始录音", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func checkPermissions() {
        // Check microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showPermissionAlert(for: "麦克风")
                }
            } else {
                print("✓ 麦克风权限已授予")
            }
        }

        // Check accessibility permission for global key monitoring
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            print("✓ 辅助功能权限已授予")
        } else {
            print("⚠️ 需要辅助功能权限才能监听全局按键")
            print("请前往: 系统设置 > 隐私与安全性 > 辅助功能")
            print("授权后需要重新启动 Typeless 应用")
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "需要\(permission)权限"
        alert.informativeText = "请在系统设置中授予 Typeless \(permission)访问权限"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            if permission == "麦克风" {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }

    private func startRecording() {
        DispatchQueue.main.async {
            self.overlayWindow?.show()
            self.recordingManager?.startRecording()
        }
    }

    private func stopRecordingAndTranscribe() {
        DispatchQueue.main.async {
            self.overlayWindow?.showProcessing()
            self.recordingManager?.stopRecording { [weak self] text in
                DispatchQueue.main.async {
                    self?.overlayWindow?.hide()
                    if let text = text, !text.isEmpty {
                        TextInserter.insertText(text)
                    }
                }
            }
        }
    }

    @objc func openSettings() {
        print(">>> openSettings() 被调用")

        // 如果设置窗口已经存在，直接显示
        if let window = settingsWindow {
            print(">>> 使用已存在的设置窗口")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 创建新的设置窗口
        print(">>> 创建新的设置窗口")
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Typeless 设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 450))
        window.center()

        // 保持窗口引用
        settingsWindow = window

        // 显示窗口
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print(">>> 设置窗口已创建并显示")
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
