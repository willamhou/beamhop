import AppKit
import CoreGraphics

/// Clipboard-Safe Paste protocol (spec §12.3). Backs up the user's clipboard per-item/per-type
/// as raw Data; if ANY type can't be serialized, it REFUSES to paste rather than risk losing
/// the user's clipboard (codex review). Restores by clearing and rebuilding every item/type.
enum ClipboardService {
    enum PasteError: Error { case clipboardUnprotectable }

    private typealias ItemSnapshot = [NSPasteboard.PasteboardType: Data]

    /// Returns nil if the clipboard can't be fully backed up (lazy/owner/file-promise types).
    private static func backup() -> [ItemSnapshot]? {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems else { return [] }   // empty clipboard = ok
        var snapshots: [ItemSnapshot] = []
        for item in items {
            var snap: ItemSnapshot = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }  // unreadable → refuse
                snap[type] = data
            }
            snapshots.append(snap)
        }
        return snapshots
    }

    /// Returns false if the clipboard might not have been fully restored (codex).
    @discardableResult
    private static func restore(_ snapshots: [ItemSnapshot]) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshots.isEmpty else { return true }
        var ok = true
        let items: [NSPasteboardItem] = snapshots.map { snap in
            let item = NSPasteboardItem()
            for (type, data) in snap { if !item.setData(data, forType: type) { ok = false } }
            return item
        }
        if !pb.writeObjects(items) { ok = false }
        return ok
    }

    private static func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 'v'
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Backup → write text → ⌘V → restore. Throws if the clipboard can't be protected.
    static func safePaste(_ text: String, pressEnter: Bool = false) throws {
        guard let snapshots = backup() else { throw PasteError.clipboardUnprotectable }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(30_000)
        sendCmdV()
        usleep(50_000)                       // spec §12.3 step 4
        if pressEnter { sendReturn() }
        usleep(30_000)
        if !restore(snapshots) {             // spec §12.3 step 5
            Notifier.error("剪贴板可能未完整恢复", "建议检查你的剪贴板")
        }
    }

    private static func sendReturn() {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
