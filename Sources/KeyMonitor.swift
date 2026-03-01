import Foundation
import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "KeyMonitor")

/// 监听全局 Fn 键按下/松开
class KeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false
    private var permissionCheckTimer: Timer?

    func startMonitoring() {
        // 单元测试环境下跳过监听（避免弹出辅助功能权限窗口）
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            logger.info("检测到单元测试环境，跳过键盘监听")
            return
        }

        // 需要辅助功能权限
        let trusted = AXIsProcessTrusted()
        logger.info("辅助功能权限状态: \(trusted ? "已授权" : "未授权", privacy: .public)")

        guard trusted else {
            logger.info("需要辅助功能权限")
            requestAccessibilityPermission()
            startPermissionPolling()
            return
        }

        // 权限已授予，停止轮询
        stopPermissionPolling()

        // 避免重复创建监听器
        guard eventTap == nil else {
            logger.debug("事件监听器已存在")
            return
        }

        // 监听 flagsChanged 事件（修饰键变化）
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        logger.debug("事件掩码: \(eventMask, privacy: .public)")

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.info("无法创建事件监听 - 请检查辅助功能权限")
            return
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.info("Fn 键监听已启动，按下 Fn 键测试")
        logger.debug("提示：如果你使用外接键盘，Fn 键检测可能不同")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 处理事件 tap 被禁用的情况
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.debug("事件监听被禁用，正在重新启用...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if type == .flagsChanged {
            let flags = event.flags
            // let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // logger.debug("FlagsChanged 事件 - keyCode: \(keyCode, privacy: .public), flags: \(flags.rawValue, privacy: .public)")

            // 检测 Fn 键状态
            // Fn 键通过 secondaryFn 标志检测
            let fnPressed = flags.contains(.maskSecondaryFn)

            // logger.debug("Fn 键状态: \(fnPressed ? \"按下\" : \"未按下\", privacy: .public), 之前状态: \(self.isFnPressed ? \"按下\" : \"未按下\", privacy: .public)")

            if fnPressed && !isFnPressed {
                // Fn 键按下
                isFnPressed = true
                logger.info("Fn 键按下，触发录音")
                DispatchQueue.main.async {
                    self.onKeyDown?()
                }
            } else if !fnPressed && isFnPressed {
                // Fn 键松开
                isFnPressed = false
                logger.info("Fn 键松开，停止录音")
                DispatchQueue.main.async {
                    self.onKeyUp?()
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    func stopMonitoring() {
        stopPermissionPolling()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// 开始轮询辅助功能权限状态
    private func startPermissionPolling() {
        stopPermissionPolling()

        logger.info("开始轮询辅助功能权限状态...")

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                logger.info("辅助功能权限已授予，重新启动监听")
                timer.invalidate()
                self?.permissionCheckTimer = nil
                DispatchQueue.main.async {
                    self?.startMonitoring()
                }
            }
        }
    }

    /// 停止权限轮询
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    deinit {
        stopMonitoring()
    }
}
