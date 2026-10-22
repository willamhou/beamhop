import AppKit
import SwiftUI
import BeamhopCore

/// Runs the production panels with fixture data and local AppKit events. Never starts
/// AppServices, accesses the user's database, requests TCC, or sends keys to another app.
enum NativeUISmoke {
    struct Check: Codable {
        let name: String
        let passed: Bool
        let detail: String
    }
    struct Snapshot: Codable {
        let file: String
        let width: Int
        let height: Int
    }
    struct Report: Codable {
        let language: String
        let appearance: String
        let os: String
        let checks: [Check]
        let snapshots: [Snapshot]
    }

    static func run(output: URL, language: String, dark: Bool) throws -> Bool {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        app.finishLaunching()
        let suffix = "\(language)-\(dark ? "dark" : "light")"
        var checks: [Check] = []
        var snapshots: [Snapshot] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append(Check(name: name, passed: passed, detail: detail))
            print("[native-ui] \(passed ? "PASS" : "FAIL") \(name) \(detail)")
        }
        func settle(_ seconds: TimeInterval = 0.3) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }
        // SwiftUI accessibility proxies can implement the informal NSObject API
        // without conforming to NSAccessibilityProtocol. Keep those nodes in the
        // traversal; dropping them makes a working control invisible to this test.
        func accessibilityNodes(_ root: NSObject) -> [NSObject] {
            var result: [NSObject] = []
            var queue: [NSObject] = [root]
            var visited = Set<ObjectIdentifier>()
            while !queue.isEmpty, result.count < 500 {
                let element = queue.removeFirst()
                guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
                result.append(element)
                // NSHostingView inherits the formal protocol from NSView, but
                // its SwiftUI tree can be exposed through the informal API.
                let legacy = element.accessibilityAttributeValue(.children) as? [Any] ?? []
                let modern = (element as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []
                let children = legacy + modern
                queue.append(contentsOf: children.compactMap { $0 as? NSObject })
            }
            return result
        }
        func identifier(_ element: NSObject) -> String? {
            (element.accessibilityAttributeValue(.identifier) as? String)
                ?? (element as? NSAccessibilityProtocol)?.accessibilityIdentifier()
        }
        func capture(_ panel: NSPanel?, name: String, expectedWidth: CGFloat) throws {
            guard let panel, let view = panel.contentView else {
                check(name + " exists", false)
                return
            }
            view.layoutSubtreeIfNeeded()
            check(name + " fits", abs(view.bounds.width - expectedWidth) < 2 && view.bounds.height > 100,
                  "content=\(view.bounds.size) fitting=\(view.fittingSize)")
            check(name + " content not clipped", view.bounds.height + 2 >= view.fittingSize.height)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                check(name + " bitmap", false)
                return
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                check(name + " PNG", false)
                return
            }
            let filename = "\(name)-\(suffix).png"
            try data.write(to: output.appendingPathComponent(filename))
            snapshots.append(Snapshot(file: filename, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        }
        func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags,
                 to panel: HandoffPanel?) -> Bool {
            guard let panel, let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else { return false }
            return panel.performKeyEquivalent(with: event)
        }
        let chinese = language == "zh-Hans"
        let excerpt = chinese
            ? "用户在浏览器里读到一段有用的信息。交接以后，仍能继续刚才的阅读。"
            : "A useful passage appears while reading. After handing it off, continue where you left off."
        let sample = Capture(source: .ax, appBundleID: "com.apple.Safari", appName: "Safari",
                             windowTitle: "Designing a quiet handoff", url: "https://example.com/design",
                             selectedText: excerpt, pid: 1, captureMethod: "fixture")
        let work = Work(name: chinese ? "让交接不打断阅读" : "Keep the reading flow",
                        boundTarget: .kimiWork, confirmedTarget: .kimiWork)
        let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        check("localization", L10n.s("Hold for later") == (chinese ? "先留着" : "Hold for later"))
        let controller = CapturePanelController()
        var confirms = 0
        var cancels = 0
        var savedNotes: [String] = []
        var held: String?
        func show() {
            controller.show(capture: sample, defaultTarget: .kimiWork,
                            visibleTargets: [.claudeCode, .kimiWork, .clipboard],
                            boundWork: work, workName: work.name, availableWorks: [work],
                            onConfirm: { _, _ in confirms += 1 }, onCancel: {
                                cancels += 1
                                savedNotes.append(controller.currentModel?.note ?? "")
                            },
                            onHold: { _, note in held = note })
            settle()
        }
        show()
        check("capture is a nonactivating panel", controller.panel?.styleMask.contains(.nonactivatingPanel) == true)
        check("capture leaves source app active", sourcePID != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID)
        check("capture can receive keyboard", controller.panel?.canBecomeKey == true)
        check("capture actually owns keyboard focus", controller.panel?.isKeyWindow == true)
        check("capture is not a document window", controller.panel?.canBecomeMain == false)
        try capture(controller.panel, name: "capture", expectedWidth: 480)
        let editor = controller.panel?.firstResponder as? NSTextView
        check("note receives initial focus", editor != nil)
        editor?.insertText("Native keyboard input", replacementRange: NSRange(location: 0, length: 0))
        settle()
        check("native editor updates note", controller.currentModel?.note == "Native keyboard input")
        editor?.insertNewline(nil)
        settle()
        check("Return inserts a line break without handoff", controller.isVisible && confirms == 0
              && controller.currentModel?.note.contains("\n") == true)
        controller.currentModel?.materials[0].text = "Edited inline <>&"
        controller.currentModel?.additionalText = "Additional material"
        check("inline material edits preserve original", controller.currentModel?.materials[0].original == sample)
        check("outgoing draft uses edited text", controller.currentModel?.snapshot.outgoingText.contains("Edited inline <>&") == true)
        check("inline addition needs no Done action", controller.currentModel?.snapshot.materials.count == 2)
        controller.currentModel?.note = "/review"
        check("slash command stays literal", controller.currentModel?.snapshot.outgoingText.hasPrefix("/review") == true)
        controller.currentModel?.materials.append(HopMaterial(name: "fixture.png", path: "/fixture.png", image: true, bytes: 1))
        check("unsupported image blocks native handoff", controller.currentModel?.canConfirm == false)
        controller.currentModel?.materials.removeLast()
        controller.currentModel?.additionalText = ""
        controller.currentModel?.materials[0].text = sample.selectedText ?? ""
        controller.currentModel?.note = ""
        let nodes = accessibilityNodes(controller.panel!)
        let accessibilityDump = nodes.map { node in
            "\(type(of: node)) id=\(identifier(node) ?? "-") formal=\(node is NSAccessibilityProtocol)"
        }.joined(separator: "\n")
        try accessibilityDump.write(to: output.appendingPathComponent("accessibility-\(suffix).txt"),
                                    atomically: true, encoding: .utf8)
        let destination = nodes.first { identifier($0) == "capture.destination" }
        check("destination control accessible", destination != nil)
        // Exercise native menu tracking and its actual action, including focus-loss behavior.
        var menuChosen = false
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
            object: nil, queue: .main) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            let timer = Timer(timeInterval: 0.1, repeats: false) { _ in
                if let index = menu.items.firstIndex(where: { $0.keyEquivalent == "3" }) {
                    menu.performActionForItem(at: index)
                    menuChosen = true
                }
                menu.cancelTracking()
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        if (destination as? NSAccessibilityProtocol)?.accessibilityPerformPress() != true {
            destination?.accessibilityPerformAction(.press)
        }
        NotificationCenter.default.removeObserver(observer)
        settle()
        check("destination menu changes receiver without dismissal", menuChosen && controller.isVisible
              && controller.currentModel?.selectedTarget == .clipboard)
        controller.currentModel?.chooseWork(work)
        check("shortcut works with menu closed", key("3", code: 20, modifiers: .command, to: controller.panel))
        check("shortcut chooses clipboard", controller.currentModel?.selectedTarget == .clipboard)
        check("shortcut leaves named work", controller.currentModel?.workName.isEmpty == true)
        check("unavailable shortcut ignored", !key("2", code: 19, modifiers: .command, to: controller.panel))
        check("Escape handled", key("\u{1b}", code: 53, modifiers: [], to: controller.panel))
        settle()
        check("Escape dismisses exactly once", !controller.isVisible && cancels == 1 && confirms == 0)
        show()
        controller.currentModel?.note = chinese ? "回头和刚才那段一起看" : "Keep this with the earlier passage"
        let replacedModel = controller.currentModel
        show()
        check("replacing a capture saves previous draft", cancels == 2
              && savedNotes.last == (chinese ? "回头和刚才那段一起看" : "Keep this with the earlier passage"))
        replacedModel?.confirm()
        replacedModel?.cancel()
        replacedModel?.hold()
        settle()
        check("replaced model callbacks cannot affect current capture", controller.isVisible
              && controller.currentModel !== replacedModel && confirms == 0 && cancels == 2 && held == nil)
        controller.currentModel?.note = chinese ? "第一行交代\n第二行说明\n第三行补充" : "First line of context\nSecond line of context\nThird line of context"
        controller.currentModel?.selectedTarget = .claudeCode
        settle()
        try capture(controller.panel, name: "capture-confirm-change", expectedWidth: 480)
        check("hold shortcut handled", key("5", code: 23, modifiers: .command, to: controller.panel))
        settle()
        check("hold dismisses and keeps note", !controller.isVisible && held?.contains(chinese ? "第三行" : "Third line") == true)
        show()
        controller.currentModel?.confirm()
        settle()
        check("confirm does not also cancel", confirms == 1 && cancels == 2)
        show()
        let otherWindow = NSWindow(contentRect: NSRect(x: 30, y: 30, width: 200, height: 100),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.makeKeyAndOrderFront(nil)
        settle()
        check("real key-window loss cancels once", !controller.isVisible && cancels == 3)
        otherWindow.orderOut(nil)

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("beamhop-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let db = try Database(path: temporary.appendingPathComponent("fixture.sqlite"))
        let store = CaptureStore(db)
        let pocketStore = PocketStore(db)
        var itemIDs: [String] = []
        for index in 1...3 {
            var item = sample
            item.id = ULID.captureID()
            item.selectedText = "\(index). \(excerpt)"
            try store.insert(item)
            let held = try pocketStore.hold(captureID: item.id,
                note: index == 1 ? (chinese ? "留意焦点的变化" : "Watch the focus change") : nil,
                intendedTarget: .clipboard, workName: index == 3 ? "Another work" : work.name)
            itemIDs.append(held.id)
        }
        let shelf = PocketWindowController()
        var completion: ((Bool) -> Void)?
        var outgoing: [String] = []
        shelf.model.configure(store: pocketStore, onDeliver: { batch, _, done in
            outgoing = batch.map { $0.0.id }
            completion = done
        })
        shelf.show()
        settle()
        check("shelf leaves source app active", NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID)
        shelf.model.toggle(itemIDs[0])
        shelf.model.toggle(itemIDs[1])
        settle()
        try capture(shelf.panel, name: "shelf-selected", expectedWidth: 360)
        _ = key("\u{1b}", code: 53, modifiers: [], to: shelf.panel)
        check("shelf Escape hides", shelf.panel?.isVisible == false)
        shelf.show()
        settle()
        check("selection survives reopening", shelf.model.selectedIDs == Set(itemIDs.prefix(2)))
        shelf.model.deliverSelection()
        check("one ordered handoff", outgoing == Array(itemIDs.prefix(2)))
        completion?(false)
        settle()
        try capture(shelf.panel, name: "shelf-retry", expectedWidth: 360)
        check("failure keeps held materials", shelf.model.count == 3 && shelf.model.selectedIDs.count == 2)
        shelf.model.deliverSelection()
        completion?(true)
        settle()
        check("success removes only selected", shelf.model.count == 1 && shelf.model.items.first?.0.id == itemIDs[2])
        try capture(shelf.panel, name: "shelf-remaining", expectedWidth: 360)
        shelf.hide()
        let library = try HopLibrary(db)
        let firstDraft = HopDraft(materials: [HopMaterial(capture: sample)],
                                  instruction: chinese ? "对照这些材料，修改方案" : "Compare these materials and update the plan",
                                  route: .init(target: .kimiWork, project: work.name))
        let secondDraft = HopDraft(materials: [HopMaterial(text: chinese ? "当前未发送的材料" : "Current unsent material")],
                                   route: .init(target: .clipboard, project: chinese ? "项目 B" : "Project B"))
        try library.hold(firstDraft)
        try library.start(secondDraft)
        // A history receipt belongs to an earlier batch, not the unsent Pocket draft.
        var preparedDraft = firstDraft
        preparedDraft.id = UUID().uuidString
        let record = try library.begin(preparedDraft)
        try library.finish(record.id, status: .prepared)
        let draftShelf = PocketWindowController()
        draftShelf.library = library
        var openedDrafts = 0
        draftShelf.onOpenDraft = { openedDrafts += 1 }
        draftShelf.show()
        settle()
        try capture(draftShelf.panel, name: "pocket-drafts", expectedWidth: 380)
        check("viewing Pocket leaves current draft intact", library.state.active == secondDraft)
        try library.restore(firstDraft.id)
        check("Pocket restore parks current input", library.state.pocket == [secondDraft] && library.state.active == firstDraft)
        try library.addMaterials(from: secondDraft)
        check("Pocket reuse keeps instruction and receiver", library.state.active?.route == firstDraft.route
              && library.state.active?.instruction == firstDraft.instruction && library.state.pocket == [secondDraft])
        settle()
        try capture(draftShelf.panel, name: "pocket-recovery", expectedWidth: 380)
        // Exercise the replacement shelf's real controls, not only its storage methods.
        let shelfModel = draftShelf.hopModel!
        shelfModel.availableTargets = [.clipboard, .kimiWork]
        var batchRecord: HopRecord?
        var batchDone: ((Bool) -> Void)?
        shelfModel.onDeliver = { batchRecord = $0; batchDone = $1 }
        func pressShelf(_ id: String) -> Bool {
            guard let panel = draftShelf.panel,
                  let node = accessibilityNodes(panel).first(where: { identifier($0) == id }) else { return false }
            node.accessibilityPerformAction(.press)
            settle()
            return true
        }
        try library.duplicate(secondDraft)
        settle()
        check("Pocket select-all control works", pressShelf("pocket.select-all") && shelfModel.selection.count == 2)
        check("Pocket inherits matching destination", shelfModel.route == secondDraft.route && shelfModel.canDeliver)
        try capture(draftShelf.panel, name: "pocket-selection", expectedWidth: 380)
        check("Pocket delete control works", pressShelf("pocket.delete") && library.state.pocket.isEmpty)
        check("Pocket undo restores selected drafts", pressShelf("pocket.undo") && library.state.pocket.count == 2)
        _ = pressShelf("pocket.select-all")
        check("Pocket batch handoff button works", pressShelf("pocket.deliver") && batchRecord?.pocketSources?.count == 2)
        if let batchRecord {
            try library.finish(batchRecord.id, status: .failed); batchDone?(false)
        }
        check("Pocket failed batch keeps selection", shelfModel.selection.count == 2 && !shelfModel.isDelivering)
        try capture(draftShelf.panel, name: "pocket-batch-retry", expectedWidth: 380)
        _ = pressShelf("pocket.deliver")
        if let batchRecord {
            try library.finish(batchRecord.id, status: .copied); batchDone?(true)
        }
        check("Pocket successful batch consumes only selected", library.state.pocket.isEmpty && library.state.active?.id == firstDraft.id)
        // History is separate and bounded; a long archive cannot expand the draft shelf.
        shelfModel.section = .history
        settle()
        try capture(draftShelf.panel, name: "pocket-history", expectedWidth: 380)
        shelfModel.section = .drafts
        for index in 1...8 {
            try library.hold(HopDraft(materials: [HopMaterial(text: (chinese ? "材料 " : "Material ") + String(index))], route: secondDraft.route))
        }
        settle()
        try capture(draftShelf.panel, name: "pocket-dense", expectedWidth: 380)
        check("Pocket list height stays bounded", (draftShelf.panel?.contentView?.bounds.height ?? 1000) < 480)
        shelfModel.query = chinese ? "材料 3" : "Material 3"
        settle()
        check("Pocket search narrows list without hidden selection", shelfModel.drafts.count == 1 && shelfModel.selectedIDs.isEmpty)
        let editedID = shelfModel.drafts.first!.id
        let opensBefore = openedDrafts
        check("Pocket edit opens the draft", pressShelf("pocket.edit." + editedID) && openedDrafts == opensBefore + 1 && library.state.active?.id == editedID)
        check("Pocket edit parks previous input", library.state.pocket.contains { $0.id == firstDraft.id })
        shelfModel.query = ""
        check("Pocket new draft control works", pressShelf("pocket.new") && library.state.active?.materials.isEmpty == true)
        draftShelf.hide()

        // Exercise project selection and creation on the production panel, without external apps.
        show()
        controller.currentModel?.usesProjectContext = true
        controller.currentModel?.workName = chinese ? "客户 A" : "Client A"
        controller.currentModel?.chooseTool(.clipboard)
        check("switching app preserves project context", controller.currentModel?.workName == (chinese ? "客户 A" : "Client A"))
        controller.currentModel?.creatingProject = true
        controller.currentModel?.isCreating = true
        settle()
        check("creation blocks accidental handoff", controller.currentModel?.canConfirm == false)
        try capture(controller.panel, name: "capture-create-project", expectedWidth: 480)
        _ = key("\u{1b}", code: 53, modifiers: [], to: controller.panel)
        settle()
        check("Escape closes creation before closing draft", controller.isVisible && controller.currentModel?.isCreating == false)
        controller.currentModel?.cancel()
        settle()
        check("real source app available for focus checks", sourcePID != nil && sourcePID != ProcessInfo.processInfo.processIdentifier,
              "sourcePID=\(sourcePID ?? -1)")
        let report = Report(language: language, appearance: dark ? "dark" : "light",
                            os: ProcessInfo.processInfo.operatingSystemVersionString,
                            checks: checks, snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output.appendingPathComponent("report-\(suffix).json"))
        return checks.allSatisfy(\.passed)
    }
}
