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
    private(set) lazy var panel = CapturePanelController()   // Week 3 floating window
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
        hotkeys.register(Hotkey(id: 1, keyCode: 49, modifiers: cmdShift, name: "⌘⇧Space Capture") {
            [weak self] in self?.doCapture()
        })
        hotkeys.register(Hotkey(id: 2, keyCode: 34, modifiers: cmdShift, name: "⌘⇧I Inbox") {
            [weak self] in self?.inbox.show()
        })
        hotkeys.register(Hotkey(id: 3, keyCode: 9, modifiers: cmdShift, name: "⌘⇧V Emergency deliver") {
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

    /// Golden path (Week 3, spec §9.1): ⌘⇧Space → floating panel (note + ⌘1/2/3/0 target pick +
    /// Enter delivers, Esc keeps it in the Inbox). Session memory of the last successful target
    /// (W3-3): in-memory only, restart resets to Claude Code — predictability over cleverness.
    ///
    /// Timing (spec §16): capture_ms and panel_ms are logged with FIXED field names — the Mac
    /// acceptance P95 data is grepped straight from these lines (P95 ≤ 300ms budget on panel_ms).
    ///
    /// Runs OFF the main thread (code review P1-1): AX reads (0.8s timeouts each) + app
    /// activation waits + pgrep would otherwise stall the hotkey→result path; AX/NSWorkspace
    /// calls are safe from a background thread. The panel show itself happens on the main thread.
    private let signposter = OSSignposter(subsystem: "com.beamhop.app", category: "perf")
    private var targetMemory = TargetMemory()   // BeamhopCore: 默认 Claude Code，仅成功投递更新

    private func doCapture() {
        guard capture != nil, delivery != nil else {
            Notifier.error(L10n.s("Database not ready — cannot capture")); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let capture = self.capture, let delivery = self.delivery else { return }
            let state = self.signposter.beginInterval("capture")
            let t0 = Date()
            let outcome = capture.captureFrontmost()
            let captureMs = Int(Date().timeIntervalSince(t0) * 1000)
            self.signposter.endInterval("capture", state, "\(captureMs)ms")
            switch outcome {
            case .duplicate:
                // W3-4: a <500ms same-window re-press is expected behavior — silent, log only.
                self.log.info("duplicate capture ignored (<500ms, same window)")
            case .rejected(let reason):
                Notifier.error(L10n.s("Capture failed"), reason)
            case .captured(let cap):
                self.log.info("captured \(cap.id, privacy: .public) method=\(cap.captureMethod, privacy: .public) capture_ms=\(captureMs)")
                DispatchQueue.main.async {
                    self.showPanel(cap, delivery: delivery)
                }
            }
        }
    }

    private func showPanel(_ cap: Capture, delivery: DeliveryService) {
        let state = signposter.beginInterval("panel_show")
        let pt0 = Date()
        panel.show(
            capture: cap,
            defaultTarget: targetMemory.last,
            onConfirm: { [weak self] target, note in
                guard let self else { return }
                guard let target else {
                    // ⌘0 仅入 Inbox: explicit no-delivery choice — tell the user it isn't lost.
                    Notifier.info(L10n.s("Saved to Inbox"), cap.id)
                    return
                }
                // Delivery off-main (AX activation sleeps); failure paths inside DeliveryService
                // degrade to clipboard and notify — never silent.
                DispatchQueue.global(qos: .userInitiated).async {
                    delivery.deliver(cap, to: target, userNote: note.isEmpty ? nil : note) { [weak self] chosen, ok in
                        if ok { self?.targetMemory.markSucceeded(chosen) }
                    }
                }
            },
            onCancel: { [weak self] in
                _ = self
                Notifier.info(L10n.s("Saved to Inbox"), cap.id)   // Esc / focus loss — capture is safe
            })
        let panelMs = Int(Date().timeIntervalSince(pt0) * 1000)
        signposter.endInterval("panel_show", state, "\(panelMs)ms")
        log.info("panel_ms=\(panelMs)")
    }
    /// ⌘⇧V emergency channel (spec §9.3): render the LATEST capture to the clipboard from
    /// anywhere — the universal fallback that never depends on AX or a running target.
    private func emergencyClipboardPaste() {
        guard let store else { Notifier.error(L10n.s("Database not ready"), L10n.s("Cannot read the latest capture")); return }
        guard let latest = (try? store.recent(limit: 1))?.first else {
            Notifier.error(L10n.s("Inbox is empty"), L10n.s("Press ⌘⇧Space to capture something first"))
            return
        }
        delivery?.deliver(latest, to: .clipboard)
    }
}
