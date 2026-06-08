import Foundation
import AppKit
import Carbon
import os
import BeamhopCore

/// Hand-rolled DI container. bootstrap() wires the foundation: storage, permissions, hotkeys,
/// menu bar, diagnostics. (Ordering note from codex: in the Xcode plan this was staged across
/// tasks; here Task 4 storage already exists, so we wire it all at once.)
final class AppServices {
    static let shared = AppServices()
    private let log = Logger(subsystem: "com.beamhop.app", category: "app")

    let permissions = PermissionService()
    let hotkeys = HotkeyManager()
    private(set) var database: Database?
    private(set) var store: CaptureStore?
    private(set) var capture: CaptureService?
    private(set) var delivery: DeliveryService?
    private(set) var menuBar: MenuBarController?
    private(set) lazy var diagnostics = DiagnosticsWindowController { [weak self] in
        var svc = DiagnosticsService()
        svc.hotkeyConflicts = self?.hotkeys.failed ?? []
        return svc
    }

    func bootstrap() {
        openDatabase()
        registerHotkeys()
        menuBar = MenuBarController(
            onCapture: { [weak self] in self?.doCapture() },
            onInbox: { [weak self] in self?.placeholderInbox() },
            onDiagnostics: { [weak self] in self?.diagnostics.show() }
        )
        firstLaunchIfNeeded()
        purgeOldCapturesInBackground()
    }

    private func openDatabase() {
        do {
            let db = try Database(path: AppPaths.databaseURL)
            self.database = db
            let store = CaptureStore(db)
            self.store = store
            self.capture = CaptureService(store: store)
            self.delivery = DeliveryService(store: store)
            log.info("database opened at \(AppPaths.databaseURL.path, privacy: .public) recovered=\(db.recoveredFromCorruption)")
        } catch {
            log.error("database open failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func registerHotkeys() {
        let cmdShift = UInt32(cmdKey | shiftKey)
        hotkeys.register(Hotkey(id: 1, keyCode: 49, modifiers: cmdShift, name: "⌘⇧Space 抓取") {
            [weak self] in self?.doCapture()
        })
        hotkeys.register(Hotkey(id: 2, keyCode: 34, modifiers: cmdShift, name: "⌘⇧I Inbox") {
            [weak self] in self?.placeholderInbox()
        })
        hotkeys.register(Hotkey(id: 3, keyCode: 9, modifiers: cmdShift, name: "⌘⇧V 应急投递") {
            [weak self] in self?.log.info("⌘⇧V (placeholder — Week 2/3)")
        })
        if !hotkeys.failed.isEmpty {
            log.warning("hotkey conflicts: \(self.hotkeys.failed.joined(separator: ", "), privacy: .public)")
        }
    }

    private func firstLaunchIfNeeded() {
        let key = "beamhop.didFirstLaunch"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
        }
        // If AX isn't granted, surface diagnostics immediately (minimal onboarding; full wizard = Week 3).
        if permissions.accessibility() == .denied {
            permissions.promptAccessibility()
            diagnostics.show()
        }
    }

    private func purgeOldCapturesInBackground() {
        guard let store else { return }
        DispatchQueue.global(qos: .utility).async {
            let n = (try? store.purgeExpired()) ?? 0
            if n > 0 { self.log.info("purged \(n) expired captures") }
        }
    }

    /// Golden path (spec §5.2, Week 2 no-floating-window version): capture → insert → deliver to
    /// default target (Claude Code) → clipboard fallback on failure → notify. Floating-window
    /// picker is Week 3.
    private func doCapture() {
        guard let capture, let delivery else {
            Notifier.error("数据库未就绪,无法抓取"); return
        }
        switch capture.captureFrontmost() {
        case .rejected(let reason):
            Notifier.error("未抓取", reason)
        case .captured(let cap):
            log.info("captured \(cap.id, privacy: .public) method=\(cap.captureMethod, privacy: .public)")
            delivery.deliver(cap, to: .claudeCode)   // default target = Claude Code (§9.1)
        }
    }
    private func placeholderInbox() {
        log.info("⌘⇧I inbox (placeholder)")
        NSSound.beep()
    }
}
