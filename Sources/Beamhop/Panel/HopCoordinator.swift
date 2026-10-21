import AppKit
import UniformTypeIdentifiers
import BeamhopCore

/// Connects the native panel, durable drafts and existing, conservative app transports.
final class HopCoordinator {
    let library: HopLibrary
    private let panel: CapturePanelController
    private let pocket: PocketWindowController
    private let hud: PocketHUDController
    private let delivery: DeliveryService
    private let captures: CaptureStore

    init(database: Database, panel: CapturePanelController, pocket: PocketWindowController,
         hud: PocketHUDController, delivery: DeliveryService, captures: CaptureStore, legacy: PocketStore) throws {
        library = try HopLibrary(database)
        self.panel = panel; self.pocket = pocket; self.hud = hud
        self.delivery = delivery; self.captures = captures
        if library.state.routes.isEmpty {
            for work in try WorkStore(database).list() {
                try library.remember(.init(target: work.boundTarget, project: work.name))
            }
        }
        // Restart-safe import: a stable draft ID makes a repeated import an update.
        for (item, capture) in try legacy.liveStack() {
            var draft = HopDraft(materials: [HopMaterial(capture: capture)], instruction: item.note ?? "",
                                 route: .init(target: item.intendedTarget, project: item.workName ?? ""))
            draft.id = "legacy-" + item.id
            try library.hold(draft)
            try legacy.remove(id: item.id)
        }
        pocket.library = library
        pocket.onOpenDraft = { [weak self] in self?.showActive() }
        pocket.onPrepareChange = { [weak self] in
            guard let self else { return false }
            if self.panel.isVisible {
                self.panel.currentModel?.isCreating = false
                self.panel.currentModel?.cancel()
            }
            return !self.panel.isVisible
        }
        hud.onOpen = { [weak pocket] in pocket?.show() }
        library.onChange = { [weak self] in self?.updateHUD() }
        updateHUD()
    }

    private func updateHUD() {
        hud.update(count: library.state.pocket.count + (library.state.active?.hasContent == true ? 1 : 0),
                   hasRecords: !library.state.records.isEmpty)
    }

    func capture(_ capture: Capture) {
        if panel.isVisible {
            panel.currentModel?.isCreating = false
            panel.currentModel?.cancel()
            guard !panel.isVisible else { return }
        }
        do {
            var materials = [HopMaterial(capture: capture)]
            if let path = capture.screenshotPath {
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                materials.append(HopMaterial(name: URL(fileURLWithPath: path).lastPathComponent, path: path,
                                             image: true, bytes: (attrs?[.size] as? NSNumber)?.int64Value ?? 0))
            }
            try library.start(HopDraft(materials: materials, route: library.state.lastRoute))
            showActive(source: capture)
        } catch { Notifier.error(L10n.s("Could not save draft"), error.localizedDescription) }
    }

    func showActive(source: Capture? = nil) {
        guard let draft = library.state.active else { return }
        pocket.hide()
        let source = source ?? draft.materials.compactMap(\.original).first
            ?? Capture(source: .ax, appBundleID: "com.beamhop.app", appName: "Beamhop",
                       pid: Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0), captureMethod: "draft")
        var record: HopRecord?
        panel.show(capture: source, defaultTarget: draft.route.target,
                   visibleTargets: TargetDetector.availableTargets(), draft: draft,
                   configure: { [weak self] model in
            guard let self else { return }
            model.usesProjectContext = true
            model.savedRoutes = self.library.state.routes
            model.projects = self.library.state.projects
            model.onDraftChange = { [weak self, weak model] draft in
                do { try self?.library.saveActive(draft); model?.draftError = nil }
                catch { model?.draftError = L10n.s("Could not save draft") + ": " + error.localizedDescription }
            }
            model.onRememberRoute = { [weak self, weak model] route in
                do {
                    try self?.library.remember(route)
                    model?.savedRoutes = self?.library.state.routes ?? []
                    model?.projects = self?.library.state.projects ?? []
                    model?.draftError = nil
                } catch { model?.draftError = error.localizedDescription }
            }
            model.onOpenPocket = { [weak self] in
                guard let self else { return }
                self.panel.currentModel?.cancel()
                if !self.panel.isVisible { self.pocket.show() }
            }
            model.onAttachmentAction = { [weak self, weak model] in
                guard let self, let model, let window = self.panel.panel else { return }
                let chooser = NSOpenPanel()
                chooser.allowsMultipleSelection = true; chooser.canChooseDirectories = false
                chooser.beginSheetModal(for: window) { [weak self, weak model] result in
                    guard result == .OK, let model else { return }
                    self?.importFiles(chooser.urls, into: model)
                }
            }
            model.onDropFiles = { [weak self, weak model] urls in
                guard let model else { return }; self?.importFiles(urls, into: model)
            }
            model.onPasteAttachments = { [weak self, weak model] in
                guard let model else { return }; self?.pasteAttachments(into: model)
            }
            model.onCopyText = { [weak self, weak model] in
                guard let self, let model else { return }
                self.copyText(model.snapshot, model: model)
            }
        }, beforeFinish: { [weak self] model, action in
            guard let self else { return false }
            do {
                let snapshot = model.snapshot
                try self.library.saveActive(snapshot)
                switch action {
                case .hold: try self.library.hold(snapshot)
                case .confirm:
                    try self.library.remember(snapshot.route)
                    if snapshot.route.target != nil { record = try self.library.begin(snapshot) }
                case .cancel: break
                }
                model.draftError = nil
                return true
            } catch { model.draftError = L10n.s("Could not save draft") + ": " + error.localizedDescription; return false }
        }, onConfirm: { [weak self] _, _ in
            guard let self else { return }
            guard let record else {
                Notifier.info(L10n.s("Saved locally"), L10n.s("Resume this draft from Pocket."))
                return
            }
            self.deliver(record)
        }, onCancel: {}, onHold: { _, _ in
            Notifier.info(L10n.s("Saved to Pocket"), L10n.s("Materials, instructions and destination are kept together."))
        })
    }

    private func deliver(_ record: HopRecord) {
        let draft = record.draft
        guard let target = draft.route.target else { return }
        if draft.route.session == .newInApp || target == .claudeCode {
            // No verified create-session API exists. Copy once and open the real app;
            // never clear its composer, synthesize New Chat, or claim a session was created.
            let copied = copy(draft.textFallback)
            let detail = draft.route.session == .newInApp
                ? L10n.s("Create a session in the receiving app, then paste. Nothing has been sent.")
                : L10n.s("Text copied. Paste into the Claude Code input after checking the terminal session.")
            finish(record, status: copied ? .copied : .failed, detail: detail)
            if copied {
                let app: NSRunningApplication?
                switch target {
                case .chatgptDesktop: app = ChatGPTDelivery.bundleIDs.compactMap { AppActivator.runningApp(bundleID: $0) }.first
                case .kimiWork: app = KimiDelivery.bundleIDs.compactMap { AppActivator.runningApp(bundleID: $0) }.first
                case .claudeCode: app = TerminalLocator.locate()?.app
                default: app = nil
                }
                app?.activate(options: [])
                Notifier.info(L10n.s("Text copied · not sent"), detail)
            }
            return
        }
        guard draft.attachments.isEmpty else {
            finish(record, status: .failed, detail: L10n.s("Attachments require manual addition in the receiving app."))
            return
        }
        do {
            // Transport receipts need a real FK. The edited payload remains separate from source captures.
            var sources = draft.materials.compactMap(\.original)
            if sources.isEmpty {
                let added = Capture(source: .ax, appBundleID: "com.beamhop.app", appName: "Beamhop",
                                    selectedText: draft.outgoingText, pid: 0, captureMethod: "manual")
                try captures.insert(added); sources = [added]
            }
            let handoff = Handoff(items: sources.map { .init(capture: $0) }, editedText: draft.outgoingText)
            delivery.deliver(handoff, to: target) { [weak self] _, succeeded in
                DispatchQueue.main.async {
                    self?.finish(record, status: succeeded ? (target == .clipboard || target == .cowork ? .copied : .prepared) : .failed,
                                 detail: succeeded ? nil : L10n.s("Check the receiving app and clipboard before retrying. The handoff backup is preserved."))
                }
            }
        } catch { finish(record, status: .failed, detail: error.localizedDescription) }
    }

    private func finish(_ record: HopRecord, status: HopRecord.Status, detail: String?) {
        do { try library.finish(record.id, status: status, detail: detail) }
        catch { Notifier.error(L10n.s("Could not save handoff status"), error.localizedDescription) }
    }
    private func copy(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
    private func copyText(_ draft: HopDraft, model: CapturePanelModel) {
        do {
            try library.saveActive(draft)
            let record = try library.begin(draft)
            let copied = copy(draft.textFallback)
            // Keep the open editor intact; copying is not consumption of a material batch.
            try library.finish(record.id, status: copied ? .copied : .failed)
            try library.saveActive(draft)
            model.draftError = copied ? nil : L10n.s("Could not copy materials")
            if copied { Notifier.info(L10n.s("Text copied · not sent"), L10n.s("Attachments require manual addition in the receiving app.")) }
        } catch { model.draftError = error.localizedDescription }
    }

    private func importFiles(_ urls: [URL], into model: CapturePanelModel) {
        let draft = model.snapshot
        model.pendingImportCount += 1
        let directory = AppPaths.supportDir.appendingPathComponent("hop-attachments", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak model] in
            var imported: [HopMaterial] = []
            var failure: String?
            for url in urls {
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                    guard values.isRegularFile == true else { continue }
                    let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destination)
                    imported.append(HopMaterial(name: url.lastPathComponent, path: destination.path,
                                                image: values.contentType?.conforms(to: .image) == true,
                                                bytes: Int64(values.fileSize ?? 0)))
                } catch { failure = error.localizedDescription }
            }
            let added = imported, message = failure
            DispatchQueue.main.async {
                guard let self else { return }
                defer { model?.pendingImportCount = max(0, (model?.pendingImportCount ?? 1) - 1) }
                if let model, self.panel.isVisible, self.panel.currentModel === model {
                    model.materials += added; model.draftError = message
                } else if !added.isEmpty {
                    let stillActive = self.library.state.active?.id == draft.id
                    var saved = (stillActive ? self.library.state.active : self.library.state.pocket.first { $0.id == draft.id })
                        ?? model?.snapshot ?? draft
                    saved.materials += added
                    do {
                        if stillActive { try self.library.saveActive(saved) }
                        else { try self.library.hold(saved) }
                    }
                    catch { Notifier.error(L10n.s("Could not save draft"), error.localizedDescription) }
                }
                if let message, !self.panel.isVisible { Notifier.error(L10n.s("Could not add attachment"), message) }
            }
        }
    }
    private func pasteAttachments(into model: CapturePanelModel) {
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles(urls, into: model); return
        }
        guard let image = NSImage(pasteboard: .general), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            let directory = AppPaths.supportDir.appendingPathComponent("hop-attachments", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString + ".png")
            try data.write(to: file, options: .atomic)
            model.materials.append(HopMaterial(name: L10n.s("Pasted image"), path: file.path, image: true, bytes: Int64(data.count)))
        } catch { model.draftError = error.localizedDescription }
    }
}
