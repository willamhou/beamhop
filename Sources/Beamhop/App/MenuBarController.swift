import AppKit

/// The menu-bar status item + menu (spec §9 / §9.3). The app runs as `.accessory` (no Dock).
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onCapture: () -> Void
    private let onInbox: () -> Void
    private let onDiagnostics: () -> Void
    private let onCompatibility: () -> Void

    init(onCapture: @escaping () -> Void,
         onInbox: @escaping () -> Void,
         onDiagnostics: @escaping () -> Void,
         onCompatibility: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onInbox = onInbox
        self.onDiagnostics = onDiagnostics
        self.onCompatibility = onCompatibility
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Beamhop")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(item("抓取当前  ⌘⇧Space", #selector(capture)))
        menu.addItem(item("Inbox  ⌘⇧I", #selector(inbox)))
        menu.addItem(.separator())
        menu.addItem(item("诊断…", #selector(diagnostics)))
        menu.addItem(item("兼容性矩阵…", #selector(compatibility)))
        menu.addItem(.separator())
        menu.addItem(item("退出 Beamhop", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func capture() { onCapture() }
    @objc private func inbox() { onInbox() }
    @objc private func diagnostics() { onDiagnostics() }
    @objc private func compatibility() { onCompatibility() }
    @objc private func quit() { NSApp.terminate(nil) }
}
