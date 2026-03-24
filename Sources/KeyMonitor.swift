import Foundation
import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "KeyMonitor")

/// 触发键配置，支持修饰键和普通键
struct TriggerKeyConfig: Codable, Equatable {
    /// 事件类型：flagsChanged (修饰键) 或 keyDown/keyUp (普通键)
    let isModifierKey: Bool
    /// 按键的 keyCode
    let keyCode: Int64
    /// 修饰键的 flag 掩码（仅修饰键有效，如 .maskSecondaryFn = 0x800000）
    let flagMask: UInt64
    /// 用户可读的按键名称
    let displayName: String

    /// 默认触发键：Fn
    static let defaultFn = TriggerKeyConfig(
        isModifierKey: true,
        keyCode: -1,  // Fn 不使用 keyCode，而是检查 flagMask
        flagMask: CGEventFlags.maskSecondaryFn.rawValue,
        displayName: "Fn"
    )

    /// 从 UserDefaults 读取，默认 Fn
    static var current: TriggerKeyConfig {
        guard let data = UserDefaults.standard.data(forKey: "triggerKeyConfig"),
              let config = try? JSONDecoder().decode(TriggerKeyConfig.self, from: data) else {
            return .defaultFn
        }
        return config
    }

    /// 保存到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "triggerKeyConfig")
        }
    }

    /// 检查事件是否匹配此触发键
    func matches(type: CGEventType, event: CGEvent) -> Bool? {
        if isModifierKey {
            guard type == .flagsChanged else { return nil }
            if keyCode >= 0 {
                // 区分左右修饰键（如 Right Command keyCode=54）
                let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
                guard eventKeyCode == keyCode else { return nil }
            }
            return event.flags.rawValue & flagMask != 0
        } else {
            let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard eventKeyCode == keyCode else { return nil }
            if type == .keyDown { return true }
            if type == .keyUp { return false }
            return nil
        }
    }
}

// MARK: - Notification for trigger key changes

extension Notification.Name {
    static let triggerKeyChanged = Notification.Name("triggerKeyChanged")
    /// Settings UI 请求进入按键录制模式
    static let triggerKeyRecordingRequested = Notification.Name("triggerKeyRecordingRequested")
    /// Settings UI 取消按键录制
    static let triggerKeyRecordingCancelled = Notification.Name("triggerKeyRecordingCancelled")
    /// KeyMonitor 录制到新按键后通知 Settings UI（object 为 TriggerKeyConfig）
    static let triggerKeyRecorded = Notification.Name("triggerKeyRecorded")
}

/// 监听全局触发键按下/松开（支持任意按键）
class KeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// 按键录制模式的回调：录制到一个按键后回调
    var onKeyRecorded: ((TriggerKeyConfig) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTriggerPressed = false
    private var permissionCheckTimer: Timer?

    /// 当前配置的触发键
    private var triggerConfig: TriggerKeyConfig = .current

    /// 是否处于按键录制模式
    var isRecordingKey = false

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

        // 监听所有需要的事件类型（修饰键 + 普通键）
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        // 刷新触发键配置
        triggerConfig = .current
        logger.info("触发键: \(self.triggerConfig.displayName, privacy: .public)")

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

        logger.info("触发键监听已启动（\(self.triggerConfig.displayName, privacy: .public)）")
    }

    /// 切换触发键后重新启动监听
    func restartWithNewTriggerKey() {
        stopMonitoring()
        isTriggerPressed = false
        triggerConfig = .current
        startMonitoring()
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

        // 按键录制模式：捕获下一个按键作为新触发键
        if isRecordingKey {
            if let config = captureKeyConfig(type: type, event: event) {
                isRecordingKey = false
                logger.info("录制到新触发键: \(config.displayName, privacy: .public) (keyCode=\(config.keyCode))")
                DispatchQueue.main.async {
                    self.onKeyRecorded?(config)
                }
                return nil  // 吞掉录制的按键事件
            }
            return Unmanaged.passRetained(event)
        }

        // 正常触发键检测模式
        if let pressed = triggerConfig.matches(type: type, event: event) {
            handleTriggerState(pressed: pressed)
            // 非修饰键需要吞掉事件，防止触发系统默认行为
            if !triggerConfig.isModifierKey {
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// 从事件中捕获按键配置（用于录制模式）
    private func captureKeyConfig(type: CGEventType, event: CGEvent) -> TriggerKeyConfig? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {
            // 修饰键：检测哪个 flag 变化了
            let flags = event.flags

            if flags.contains(.maskSecondaryFn) {
                return TriggerKeyConfig(isModifierKey: true, keyCode: -1,
                                        flagMask: CGEventFlags.maskSecondaryFn.rawValue, displayName: "Fn")
            }
            if flags.contains(.maskCommand) {
                let name = keyCode == 54 ? "Right Command ⌘" : "Left Command ⌘"
                return TriggerKeyConfig(isModifierKey: true, keyCode: keyCode,
                                        flagMask: CGEventFlags.maskCommand.rawValue, displayName: name)
            }
            if flags.contains(.maskAlternate) {
                let name = keyCode == 61 ? "Right Option ⌥" : "Left Option ⌥"
                return TriggerKeyConfig(isModifierKey: true, keyCode: keyCode,
                                        flagMask: CGEventFlags.maskAlternate.rawValue, displayName: name)
            }
            if flags.contains(.maskControl) {
                let name = keyCode == 62 ? "Right Control ⌃" : "Left Control ⌃"
                return TriggerKeyConfig(isModifierKey: true, keyCode: keyCode,
                                        flagMask: CGEventFlags.maskControl.rawValue, displayName: name)
            }
            if flags.contains(.maskShift) {
                let name = keyCode == 60 ? "Right Shift ⇧" : "Left Shift ⇧"
                return TriggerKeyConfig(isModifierKey: true, keyCode: keyCode,
                                        flagMask: CGEventFlags.maskShift.rawValue, displayName: name)
            }
            return nil
        }

        if type == .keyDown {
            // 普通键：用 keyCode 标识
            let name = keyCodeDisplayName(keyCode)
            return TriggerKeyConfig(isModifierKey: false, keyCode: keyCode,
                                    flagMask: 0, displayName: name)
        }

        return nil
    }

    /// 将 keyCode 转为人类可读名称
    private func keyCodeDisplayName(_ keyCode: Int64) -> String {
        // 常见特殊键
        switch keyCode {
        case 110: return "App / Menu"
        case 53: return "Escape"
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 117: return "Forward Delete"
        case 114: return "Insert"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        default:
            // 尝试用 Carbon 获取字符名称
            if let char = keyCodeToCharacter(keyCode) {
                return String(char).uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    /// 将 keyCode 转为字符（用于字母/数字键）
    private func keyCodeToCharacter(_ keyCode: Int64) -> Character? {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source!, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            0, // no modifiers
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return Character(UnicodeScalar(chars[0])!)
    }

    /// 统一处理触发键状态变化
    private func handleTriggerState(pressed: Bool) {
        if pressed && !isTriggerPressed {
            isTriggerPressed = true
            logger.info("\(self.triggerConfig.displayName, privacy: .public) 按下，触发录音")
            DispatchQueue.main.async {
                self.onKeyDown?()
            }
        } else if !pressed && isTriggerPressed {
            isTriggerPressed = false
            logger.info("\(self.triggerConfig.displayName, privacy: .public) 松开，停止录音")
            DispatchQueue.main.async {
                self.onKeyUp?()
            }
        }
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
