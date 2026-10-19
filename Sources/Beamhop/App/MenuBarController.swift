import AppKit
import BeamhopCore

/// The menu-bar status item + menu (spec §9 / §9.3). The app runs as `.accessory` (no Dock).
/// All titles go through L10n.s; the in-app Language submenu flips the per-app
/// `AppleLanguages` override (PROGRESS §7.C, 2026-10-19) and relaunches to apply —
/// SwiftUI literals + these titles pick up zh-Hans.lproj from the bundle on next launch.
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
        menu.addItem(item(L10n.s("Capture frontmost  ⌘⇧Space"), #selector(capture)))
        menu.addItem(item(L10n.s("Inbox  ⌘⇧I"), #selector(inbox)))
        menu.addItem(.separator())
        menu.addItem(item(L10n.s("Diagnostics…"), #selector(diagnostics)))
        menu.addItem(item(L10n.s("Compatibility Matrix…"), #selector(compatibility)))
        menu.addItem(languageMenuItem())
        menu.addItem(.separator())
        menu.addItem(item(L10n.s("Quit Beamhop"), #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    // MARK: language (per-app AppleLanguages override; applied on relaunch)

    private enum AppLanguage: String {
        case english = "en"
        case chinese = "zh-Hans"
        case system = ""
    }

    private var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? ""
        if raw.hasPrefix("zh") { return .chinese }
        if raw.hasPrefix("en") { return .english }
        return .system
    }

    private func languageMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        // Language names render in their OWN language regardless of the UI language.
        for (title, lang) in [("English", AppLanguage.english), ("简体中文", AppLanguage.chinese)] {
            let i = NSMenuItem(title: title, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = lang.rawValue
            i.state = (currentLanguage == lang) ? .on : .off
            submenu.addItem(i)
        }
        let i = NSMenuItem(title: L10n.s("Language"), action: nil, keyEquivalent: "")
        i.submenu = submenu
        return i
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: raw), lang != currentLanguage else { return }
        if lang == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        }
        let alert = NSAlert()
        alert.messageText = L10n.s("Restart Beamhop now to apply the language change?")
        alert.informativeText = L10n.s("The new language takes effect after Beamhop restarts.")
        alert.addButton(withTitle: L10n.s("Restart Now"))
        alert.addButton(withTitle: L10n.s("Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchAfterTerminate()
        }
    }

    /// Launch a fresh instance, then terminate this one — `open -n` is detached so it
    /// survives our exit.
    private func relaunchAfterTerminate() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        do {
            try task.run()
            Thread.sleep(forTimeInterval: 0.4)   // let launchd register the new instance first
        } catch {
            // fall back to a plain quit — the user reopens manually
        }
        NSApp.terminate(nil)
    }

    @objc private func capture() { onCapture() }
    @objc private func inbox() { onInbox() }
    @objc private func diagnostics() { onDiagnostics() }
    @objc private func compatibility() { onCompatibility() }
    @objc private func quit() { NSApp.terminate(nil) }
}
