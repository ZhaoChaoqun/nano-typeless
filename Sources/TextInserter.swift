import Foundation
import AppKit
import Carbon.HIToolbox

/// 文字插入工具 - 将文字插入到当前光标位置
struct TextInserter {

    /// 将文字插入到当前活动应用的光标位置
    static func insertText(_ text: String) {
        // 使用剪贴板 + 粘贴命令的方式插入文字
        // 这是最可靠的方式，因为直接模拟键盘输入对中文支持不好

        let pasteboard = NSPasteboard.general

        // 保存完整的剪贴板内容（所有类型）
        let savedItems = savePasteboardContents(pasteboard)
        let changeCountBefore = pasteboard.changeCount

        // 设置新文字到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 模拟 Cmd+V 粘贴
        simulatePaste()

        // 恢复原来的剪贴板内容（延迟执行，确保粘贴完成）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 只有在我们的粘贴操作后剪贴板没有被外部修改过时才恢复
            // changeCount 在每次 clearContents/setString 后递增
            // 我们做了 clearContents + setString = +2，如果外部又修改了则 > changeCountBefore + 2
            let expectedCount = changeCountBefore + 2
            if pasteboard.changeCount == expectedCount {
                restorePasteboardContents(pasteboard, items: savedItems)
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

    // MARK: - Pasteboard Save/Restore

    /// 保存剪贴板中所有 item 的所有类型数据
    private static func savePasteboardContents(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }

    /// 恢复剪贴板内容
    private static func restorePasteboardContents(_ pasteboard: NSPasteboard, items: [[(NSPasteboard.PasteboardType, Data)]]) {
        guard !items.isEmpty else { return }

        pasteboard.clearContents()
        let pasteboardItems = items.map { typesAndData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typesAndData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    // MARK: - Key Simulation

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
}
