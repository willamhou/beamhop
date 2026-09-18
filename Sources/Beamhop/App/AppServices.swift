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
    private(set) lazy var inbox = InboxWindowController()
    private(set) lazy var compatibility = CompatibilityWindowController()
    private(set) lazy var firstRun = FirstRunWindowController(
        permissions: permissions,
        onOpenDiagnostics: { [weak self] in self?.diagnostics.show() })

    func bootstrap() {
        openDatabase()
        BrowserBridgeServer.shared.start()   // Week 2B: listen for the browser extension's host
        registerHotkeys()
        menuBar = MenuBarController(
            onCapture: { [weak self] in self?.doCapture() },
            onInbox: { [weak self] in self?.inbox.show() },
            onDiagnostics: { [weak self] in self?.diagnostics.show() },
            onCompatibility: { [weak self] in self?.compatibility.show() }
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
            inbox.model.configure(store: store) { [weak self] capture, target in
                // delivery does AX activation + usleep — never on the main thread
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.delivery?.deliver(capture, to: target)
                }
            }
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
            [weak self] in self?.inbox.show()
        })
        hotkeys.register(Hotkey(id: 3, keyCode: 9, modifiers: cmdShift, name: "⌘⇧V 应急投递") {
            [weak self] in self?.emergencyClipboardPaste()
        })
        if !hotkeys.failed.isEmpty {
            log.warning("hotkey conflicts: \(self.hotkeys.failed.joined(separator: ", "), privacy: .public)")
        }
    }

    private func firstLaunchIfNeeded() {
        let key = "beamhop.didFirstLaunch"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            firstRun.show()
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
    ///
    /// Runs OFF the main thread (code review P1-1): AX reads (0.8s timeouts each) + app
    /// activation waits + pgrep would otherwise stall the hotkey→result path; AX/NSWorkspace
    /// calls are safe from a background thread.
    private func doCapture() {
        guard capture != nil, delivery != nil else {
            Notifier.error("数据库未就绪,无法抓取"); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let capture = self.capture, let delivery = self.delivery else { return }
            switch capture.captureFrontmost() {
            case .rejected(let reason):
                Notifier.error("未抓取", reason)
            case .captured(let cap):
                self.log.info("captured \(cap.id, privacy: .public) method=\(cap.captureMethod, privacy: .public)")
                delivery.deliver(cap, to: .claudeCode)   // default target = Claude Code (§9.1)
            }
        }
    }
    /// ⌘⇧V emergency channel (spec §9.3): render the LATEST capture to the clipboard from
    /// anywhere — the universal fallback that never depends on AX or a running target.
    private func emergencyClipboardPaste() {
        guard let store else { Notifier.error("数据库未就绪", "无法读取最新 Capture"); return }
        guard let latest = (try? store.recent(limit: 1))?.first else {
            Notifier.error("Inbox 为空", "先按 ⌘⇧Space 抓取一条")
            return
        }
        delivery?.deliver(latest, to: .clipboard)
    }
}
