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
    private(set) var pocketStore: PocketStore?
    private(set) var workStore: WorkStore?
    private(set) var capture: CaptureService?
    private(set) var delivery: DeliveryService?
    private(set) var menuBar: MenuBarController?
    private(set) lazy var diagnostics = DiagnosticsWindowController { [weak self] in
        var svc = DiagnosticsService()
        svc.hotkeyConflicts = self?.hotkeys.failed ?? []
        return svc
    }
    private(set) lazy var inbox = InboxWindowController()
    private(set) lazy var pocket = PocketWindowController()   // 「先留着」hold stack (essay 01)
    private(set) lazy var pocketHUD = PocketHUDController()    // bottom-right chip showing the stack exists
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
            onPocket: { [weak self] in self?.pocket.show() },
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
            let pocketStore = PocketStore(db)
            self.pocketStore = pocketStore
            let workStore = WorkStore(db)
            self.workStore = workStore
            self.capture = CaptureService(store: store)
            self.delivery = DeliveryService(store: store)
            inbox.model.configure(store: store, events: events) { [weak self] capture, target in
                // delivery does AX activation + usleep — never on the main thread
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.delivery?.deliver(capture, to: target)
                }
            }
            let hud = self.pocketHUD
            hud.onOpen = { [weak self] in self?.pocket.show() }
            pocket.model.configure(store: pocketStore,
                                   onDeliver: { [weak self] batch, target, completion in
                self?.deliverPocketBatch(batch, to: target, completion: completion)
            }, onCountChange: { [weak hud] count in
                hud?.update(count: count)
            })
            // boot state: if the pocket already holds items (previous session), show the chip
            pocket.model.reload()
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
        hotkeys.register(Hotkey(id: 4, keyCode: 35, modifiers: cmdShift, name: "⌘⇧P Pocket") {
            [weak self] in self?.pocket.show()
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

        // Essay 02: re-bind the remembered named destination (if any) and surface an
        // unconfirmed receiver change. The panel pre-selects the work's CURRENT binding —
        // the first Enter then only acknowledges the change, the second delivers.
        let rememberedWork = targetMemory.lastWorkName.flatMap { name in
            try? workStore?.fetch(name: name)
        }
        let defaultTarget = rememberedWork?.boundTarget ?? targetMemory.last
        // Only offer destinations that are REAL on this machine (no fake choices);
        // the model falls back gracefully if the remembered target vanished.
        let visibleTargets = TargetDetector.availableTargets()

        panel.show(
            capture: cap,
            defaultTarget: defaultTarget,
            visibleTargets: visibleTargets,
            boundWork: rememberedWork,
            workName: rememberedWork?.name ?? "",
            availableWorks: (try? workStore?.list()) ?? [],
            onConfirm: { [weak self] target, note in
                guard let self else { return }
                self.events?.record(name: EventStore.Name.panelConfirm,
                                    detail: "target=\(target?.rawValue ?? "inbox_only")")
                let workName = self.panel.currentModel?.workName
                self.registerOrRebindWork(workName: workName, chosenTarget: target)
                self.saveNote(note, for: cap.id)
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
                        DispatchQueue.main.async {
                            if ok {
                                self.targetMemory.markSucceeded(chosen, workName: workName)
                                if let workName, let work = try? self.workStore?.fetch(name: workName),
                                   work.needsConfirmation {
                                    try? self.workStore?.confirm(id: work.id)
                                }
                            }
                            // Clipboard keeps the source app; prepared drafts stay visible for review.
                            self.restorePrePanelFocus()
                        }
                    }
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
                // Esc / focus loss — capture is safe in the Inbox; hand focus back so the next
                // ⌘⇧Space captures the real work, not us.
                self.saveNote(self.panel.currentModel?.note ?? "", for: cap.id)
                self.events?.record(name: EventStore.Name.panelCancel, captureID: cap.id)
                Notifier.info(L10n.s("Saved to Inbox"), cap.id)
                self.restorePrePanelFocus()
            },
            onHold: { [weak self] target, note in
                guard let self, let pocketStore else { return }
                // 「先留着」(essay 01): park in the pocket — order, note and intended target
                // survive; nothing is delivered, reading position stays put.
                do {
                    let item = try pocketStore.hold(captureID: cap.id,
                                                    note: note.isEmpty ? nil : note,
                                                    intendedTarget: target,
                                                    workName: self.panel.currentModel?.workName)
                    self.events?.record(name: EventStore.Name.pocketHold,
                                        detail: "target=\(target?.rawValue ?? "undecided")",
                                        captureID: cap.id)
                    let n = (try? pocketStore.count()) ?? 0
                    self.pocket.model.reload()   // fires the bottom-right HUD count
                    Notifier.info(L10n.f("Held in pocket (%lld)", Int64(n)),
                                  L10n.s("Press ⌘⇧P to review and send"))
                    self.log.info("held \(item.id, privacy: .public) stack=\(n)")
                } catch {
                    self.log.error("pocket hold failed: \(String(describing: error), privacy: .public)")
                    Notifier.error(L10n.s("Could not hold"), String(describing: error))
                }
                self.restorePrePanelFocus()
            })
        let panelMs = Int(Date().timeIntervalSince(pt0) * 1000)
        signposter.endInterval("panel_show", state, "\(panelMs)ms")
        log.info("panel_ms=\(panelMs)")
        events?.record(name: EventStore.Name.panelShown, detail: "ms=\(panelMs)", captureID: cap.id)
    }

    /// Essay 02 destination bookkeeping at confirm time:
    /// - new name → register (the act of naming + choosing IS the first confirmation);
    /// - existing work, user picked a DIFFERENT target in this panel → explicit in-panel
    ///   rebind: the pick itself verifies the address, so rebind + confirm together;
    /// - existing work, same target → leave confirmation state untouched (a separate
    ///   rebind elsewhere may still require the two-step ack in the panel).
    private func registerOrRebindWork(workName: String?, chosenTarget: DeliveryTarget?) {
        guard let workStore, let raw = workName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let target = chosenTarget else { return }
        do {
            if let existing = try workStore.fetch(name: raw) {
                if existing.boundTarget != target {
                    // Record the new address, but DO NOT confirm here: the two-step gate in
                    // CapturePanelModel already made the user acknowledge the change, and the
                    // post-delivery callback below is what actually verifies the address
                    // (delivery succeeded). Rebinding without a successful delivery leaves
                    // needsConfirmation true — honest state if the delivery never lands.
                    _ = try workStore.rebind(id: existing.id, to: target)
                    log.info("work '\(raw, privacy: .public)' rebound \(existing.boundTarget.rawValue) → \(target.rawValue)")
                }
            } else {
                _ = try workStore.register(name: raw, boundTo: target)
                log.info("work registered: \(raw, privacy: .public) → \(target.rawValue, privacy: .public)")
            }
        } catch {
            log.error("work bookkeeping failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Selected materials are one payload and one transport operation. No per-item paste.
    private func deliverPocketBatch(_ batch: [PocketModel.Pair], to target: DeliveryTarget,
                                    completion: @escaping (Bool) -> Void) {
        guard let delivery else { completion(false); return }
        events?.record(name: EventStore.Name.pocketBatch, detail: "count=\(batch.count)")
        let handoff = Handoff(items: batch.map { .init(capture: $0.1, note: $0.0.note) })
        delivery.deliver(handoff, to: target) { [weak self] _, ok in
            DispatchQueue.main.async {
                for (item, _) in batch {
                    self?.events?.record(name: ok ? EventStore.Name.pocketItemDelivered : EventStore.Name.pocketItemFailed,
                                         detail: "target=\(target.rawValue)", captureID: item.captureID)
                }
                completion(ok)
            }
        }
    }

    private func saveNote(_ note: String, for captureID: String) {
        do { try store?.setUserNote(note.isEmpty ? nil : note, captureID: captureID) }
        catch { Notifier.error(L10n.s("Could not save note"), String(describing: error)) }
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
