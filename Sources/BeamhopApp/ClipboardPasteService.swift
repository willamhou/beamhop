import AppKit
import CoreGraphics
import Foundation

enum ClipboardPasteError: LocalizedError {
    case backupFailed(String)
    case writeFailed
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .backupFailed(let type):
            "无法备份剪贴板类型 \(type)，已拒绝自动粘贴以避免污染现有内容。"
        case .writeFailed:
            "无法写入系统剪贴板。"
        case .eventCreationFailed:
            "无法生成粘贴按键事件，请检查辅助功能权限。"
        }
    }
}

private struct PasteboardSnapshot {
    var items: [[NSPasteboard.PasteboardType: Data]]
}

@MainActor
final class ClipboardPasteService {
    private let pasteboard = NSPasteboard.general

    func safePaste(text: String, autoSubmit: Bool) async throws {
        let snapshot = try backup()
        do {
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw ClipboardPasteError.writeFailed
            }
            try postKey(keyCode: 9, command: true) // V
            try await Task.sleep(nanoseconds: 80_000_000)
            try restore(snapshot)
            if autoSubmit {
                try postKey(keyCode: 36, command: false) // Return
            }
        } catch {
            try? restore(snapshot)
            throw error
        }
    }

    /// Failure recovery deliberately leaves the rendered prompt on the clipboard.
    func copyForManualHandoff(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardPasteError.writeFailed
        }
    }

    private func backup() throws -> PasteboardSnapshot {
        let copiedItems = try (pasteboard.pasteboardItems ?? []).map { item in
            var copied: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw ClipboardPasteError.backupFailed(type.rawValue)
                }
                copied[type] = data
            }
            return copied
        }
        return PasteboardSnapshot(items: copiedItems)
    }

    private func restore(_ snapshot: PasteboardSnapshot) throws {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let restoredItems = snapshot.items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: type)
            }
            return item
        }
        guard pasteboard.writeObjects(restoredItems) else {
            throw ClipboardPasteError.writeFailed
        }
    }

    private func postKey(keyCode: CGKeyCode, command: Bool) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ClipboardPasteError.eventCreationFailed
        }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
