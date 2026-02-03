import Foundation
import AppKit
import Carbon.HIToolbox

/// 文字插入工具 - 将文字插入到当前光标位置
struct TextInserter {

    /// 将文字插入到当前活动应用的光标位置
    static func insertText(_ text: String) {
        // 使用剪贴板 + 粘贴命令的方式插入文字
        // 这是最可靠的方式，因为直接模拟键盘输入对中文支持不好

        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // 设置新文字到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 模拟 Cmd+V 粘贴
        simulatePaste()

        // 恢复原来的剪贴板内容（延迟执行，确保粘贴完成）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// 插入文字（不保存/恢复剪贴板，用于流式输入）
    static func insertTextDirect(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulatePaste()
    }

    /// 删除指定数量的字符（模拟 Backspace）
    static func deleteCharacters(_ count: Int) {
        guard count > 0 else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        let backspaceKeyCode: CGKeyCode = 51  // Backspace 键码

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: false) else {
                continue
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            // 短暂延迟确保按键被处理
            usleep(5000)  // 5ms
        }
    }

    /// 模拟 Cmd+V 粘贴操作
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // V 键的虚拟键码
        let vKeyCode: CGKeyCode = 9

        // 创建按下 Cmd+V 事件
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            return
        }
        keyDown.flags = .maskCommand

        // 创建松开 Cmd+V 事件
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyUp.flags = .maskCommand

        // 发送事件
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// 直接通过模拟键盘输入文字（备用方案，对中文支持不好）
    static func insertTextViaKeyboard(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text.unicodeScalars {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }

            var unicodeChar = UniChar(char.value)
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyDown.post(tap: .cghidEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
