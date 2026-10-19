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
    private(set) var events: EventStore?
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
            let events = EventStore(db)
            self.events = events
            self.capture = CaptureService(store: store)
            self.delivery = DeliveryService(store: store)
            inbox.model.configure(store: store, events: events) { [weak self] capture, target in
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
            // dogfood events: generous 180-day retention, pruned alongside captures
            _ = try? self.events?.prune()
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
    /// §7-C dogfood fix: showing the panel activates Beamhop, and nothing used to reactivate the
    /// previous app after Esc / Inbox-only confirm — so the next ⌘⇧Space captured Beamhop itself
    /// (0ms, useless row). Recorded at capture time; restored after panel-close paths that leave
    /// no other app in front (cancel, ⌘0 Inbox-only, delivery degraded to clipboard).
    private var appBeforePanel: NSRunningApplication?

    private static let ownBundleID = "com.beamhop.app"

    private func doCapture() {
        guard capture != nil, delivery != nil else {
            Notifier.error(L10n.s("Database not ready — cannot capture")); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let capture = self.capture, let delivery = self.delivery else { return }
            // Before capture records its own frontmost, remember OUR pre-panel frontmost — but
            // never chain a residue: if Beamhop is somehow still frontmost (previous restore
            // missed), keep the older remembered app instead of capturing Beamhop-on-Beamhop.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Self.ownBundleID {
                self.appBeforePanel = NSWorkspace.shared.frontmostApplication
            }
            let state = self.signposter.beginInterval("capture")
            let t0 = Date()
            let outcome = capture.captureFrontmost()
            let captureMs = Int(Date().timeIntervalSince(t0) * 1000)
            self.signposter.endInterval("capture", state, "\(captureMs)ms")
            switch outcome {
            case .duplicate:
                // W3-4: a <500ms same-window re-press is expected behavior — silent, log only.
                self.log.info("duplicate capture ignored (<500ms, same window)")
                self.events?.record(name: EventStore.Name.captureDuplicate)
            case .rejected(let reason):
                Notifier.error(L10n.s("Capture failed"), reason)
                self.events?.record(name: EventStore.Name.captureRejected, detail: "reason=\(reason)")
            case .captured(let cap):
                self.log.info("captured \(cap.id, privacy: .public) method=\(cap.captureMethod, privacy: .public) capture_ms=\(captureMs)")
                self.events?.record(name: EventStore.Name.captureCompleted,
                                    detail: "method=\(cap.captureMethod) ms=\(captureMs)",
                                    captureID: cap.id)
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
                self.events?.record(name: EventStore.Name.panelConfirm,
                                    detail: "target=\(target?.rawValue ?? "inbox_only")")
                guard let target else {
                    // ⌘0 仅入 Inbox: explicit no-delivery choice — tell the user it isn't lost,
                    // then hand focus back so the next ⌘⇧Space captures the real work, not us.
                    Notifier.info(L10n.s("Saved to Inbox"), cap.id)
                    self.restorePrePanelFocus()
                    return
                }
                // Delivery off-main (AX activation sleeps); failure paths inside DeliveryService
                // degrade to clipboard and notify — never silent.
                DispatchQueue.global(qos: .userInitiated).async {
                    // self is already bound strongly by the outer onConfirm guard; capturing it
                    // weakly here only re-triggers #ImplicitStrongCapture (outer strong scope).
                    delivery.deliver(cap, to: target, userNote: note.isEmpty ? nil : note) { chosen, ok in
                        if ok { self.targetMemory.markSucceeded(chosen) }
                        // Degraded to clipboard (focus/paste/registration failure): nothing else
                        // took focus, so restore — same residue as Esc. On success the target app
                        // is frontmost and the guard inside makes this a no-op.
                        else { self.restorePrePanelFocus() }
                    }
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
                // Esc / focus loss — capture is safe in the Inbox; hand focus back so the next
                // ⌘⇧Space captures the real work, not us.
                self.events?.record(name: EventStore.Name.panelCancel, captureID: cap.id)
                Notifier.info(L10n.s("Saved to Inbox"), cap.id)
                self.restorePrePanelFocus()
            })
        let panelMs = Int(Date().timeIntervalSince(pt0) * 1000)
        signposter.endInterval("panel_show", state, "\(panelMs)ms")
        log.info("panel_ms=\(panelMs)")
        events?.record(name: EventStore.Name.panelShown, detail: "ms=\(panelMs)", captureID: cap.id)
    }

    /// §7-C: reactivate the app that was frontmost before the panel took key — best-effort, and
    /// ONLY when Beamhop is still frontmost (never steal focus from a delivery that succeeded).
    /// Runs on the main queue after a beat so orderOut has settled before the re-activation.
    private func restorePrePanelFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let prev = self.appBeforePanel,
                  prev.bundleIdentifier != Self.ownBundleID,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.ownBundleID
            else { return }
            prev.activate(options: [.activateAllWindows])
            self.log.info("restored focus to \(prev.bundleIdentifier ?? "?", privacy: .public)")
        }
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
