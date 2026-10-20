#if DEBUG
import AppKit
import SwiftUI
import BeamhopCore

/// Opt-in native regression harness. Uses its own fixture apps and temporary database; never
/// bootstraps AppServices, registers hotkeys, pastes, or opens the user's Inbox.
enum UIRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func fixture() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 420, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Beamhop regression fixture"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text("Temporary focus test — no user content").padding())
        app.finishLaunching()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func run(output: URL) -> Int32 {
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.finishLaunching()
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("beamhop-ui-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let path = temp.appendingPathComponent("inbox.sqlite")
            let store = CaptureStore(try Database(path: path))

            let sourceProcess = try launchFixture()
            defer { if sourceProcess.isRunning { sourceProcess.terminate(); sourceProcess.waitUntilExit() } }
            let source = try waitForApp(sourceProcess)
            let destinationProcess = try launchFixture()
            defer { if destinationProcess.isRunning { destinationProcess.terminate(); destinationProcess.waitUntilExit() } }
            let destination = try waitForApp(destinationProcess)

            let cap = Capture(source: .ax, appBundleID: source.bundleIdentifier ?? "unknown", appName: "Regression Source",
                              windowTitle: "Focus and Inbox regression", url: "https://example.com/pr/42",
                              selectedText: "Original evidence for the agent conclusion.",
                              pid: Int(source.processIdentifier), captureMethod: "fixture")
            try store.insert(cap)
            let panel = CapturePanelController()
            var cancelCount = 0
            func show(_ capture: Capture? = nil, target: DeliveryTarget? = nil) throws {
                // The source remains active while the nonactivating panel takes keyboard
                // input. Wait for any previous activation before opening the next panel.
                if frontPID != source.processIdentifier { source.activate(options: []) }
                try wait("source activates") { frontPID == source.processIdentifier && !NSApp.isActive }
                panel.show(capture: capture ?? cap, defaultTarget: target, onConfirm: { _, _ in },
                           onCancel: { cancelCount += 1 })
                // NSApp.isActive can become true when a nonactivating panel takes key input.
                // NSWorkspace's foreground PID is the source-activation contract.
                try wait("panel owns keyboard while source stays active") {
                    frontPID == source.processIdentifier
                        && panel.isVisible && panel.panel?.isKeyWindow == true
                }
            }

            // Exercise the actual self-capture guard separately: normal panel presentation
            // must never activate Beamhop merely to make this regression pass.
            app.activate(ignoringOtherApps: true)
            try wait("Beamhop activates for the self-capture guard") {
                frontPID == ProcessInfo.processInfo.processIdentifier && NSApp.isActive
            }
            if case .rejected = CaptureService(store: store).captureFrontmost() {
                try expect(try store.count() == 1, "self capture does not create a row")
            } else { throw Failure(description: "self-capture guard did not reject the app") }
            try show()
            panel.currentModel?.cancel()
            try wait("Esc restores the source") { frontPID == source.processIdentifier && !panel.isVisible }
            try expect(cancelCount == 1, "cancel callback fires exactly once")

            let restoreTargets: [DeliveryTarget?] = [nil, .clipboard, .cowork]
            for target in restoreTargets {
                try show(target: target)
                panel.currentModel?.confirm()
                try wait("save/clipboard restores source: \(target?.rawValue ?? "Inbox")") {
                    frontPID == source.processIdentifier && !panel.isVisible
                }
            }

            try show(target: .chatgptDesktop)
            panel.currentModel?.confirm()
            destination.activate(options: [])
            try wait("destination activates") { frontPID == destination.processIdentifier }
            panel.restoreSourceIfStillActive(captureID: cap.id)
            pump(seconds: 0.2)
            try expect(frontPID == destination.processIdentifier, "delivery completion keeps destination focus")

            try show()
            destination.activate(options: [])
            try wait("click-away cancels panel") { !panel.isVisible && frontPID == destination.processIdentifier }
            try expect(cancelCount == 2, "click-away callback fires once and does not steal focus")

            for index in 1...20 {
                try show()
                panel.currentModel?.cancel()
                try wait("repeat open/cancel \(index)/20 restores source") {
                    frontPID == source.processIdentifier && !panel.isVisible
                }
            }

            let newer = Capture(source: .ax, appBundleID: cap.appBundleID, appName: cap.appName,
                                windowTitle: "New capture", pid: cap.pid, captureMethod: "fixture")
            try show(newer)
            panel.restoreSourceIfStillActive(captureID: cap.id)
            pump(seconds: 0.2)
            try expect(panel.isVisible && panel.panel?.isKeyWindow == true && frontPID == source.processIdentifier,
                       "late old delivery cannot dismiss a newer panel")
            panel.currentModel?.cancel()

            let inbox = InboxWindowController()
            inbox.model.configure(store: store, events: nil, onDeliver: { _, _ in })
            try show()
            inbox.show()
            // A key-window change can precede the foreground activation notification.
            try wait("Inbox becomes foreground and cancels panel") {
                !panel.isVisible && NSApp.keyWindow?.title == "Beamhop Inbox"
                    && frontPID == ProcessInfo.processInfo.processIdentifier
            }
            panel.restoreSourceIfStillActive(captureID: cap.id)
            pump(seconds: 0.2)
            try expect(frontPID == ProcessInfo.processInfo.processIdentifier, "Inbox keeps its own focus")
            inbox.model.selectedID = cap.id
            try expect(inbox.model.selectedResults.isEmpty, "Inbox starts with empty conclusion state")
            try saveViaMCP(path: path, captureID: cap.id)
            let writer = try ResultStore.open(path: path)
            try wait("visible Inbox polls external MCP process write-back", timeout: 4) {
                inbox.model.selectedResults.count == 1
            }
            try writer.insert(CaptureResult(originCaptureID: cap.id, agent: "claude_code", sessionID: "regression-2",
                                            content: String(repeating: "完整证据保留。", count: 360)))
            try wait("second agent conclusion appears", timeout: 4) {
                inbox.model.selectedResults.count == 2
            }
            try expect(inbox.model.resultCounts[cap.id] == 2, "Inbox badge tracks both agents")
            if let window = NSApp.keyWindow {
                window.setContentSize(NSSize(width: 1400, height: 950))
                window.appearance = NSAppearance(named: .aqua)
                let view = NSHostingView(rootView: InboxView(model: inbox.model).environment(\.colorScheme, .light))
                window.contentView = view
                pump(seconds: 0.3)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw Failure(description: "could not render Inbox")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                // cacheDisplay leaves SwiftUI material backgrounds transparent; flatten onto
                // the fixture's light background so previews are legible outside AppKit.
                let image = NSImage(size: view.bounds.size)
                image.lockFocus()
                NSColor.white.setFill()
                NSBezierPath.fill(NSRect(origin: .zero, size: view.bounds.size))
                bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation,
                      let flat = NSBitmapImageRep(data: tiff),
                      let png = flat.representation(using: .png, properties: [:]) else {
                    throw Failure(description: "could not encode Inbox PNG")
                }
                try png.write(to: output.appendingPathComponent("inbox-results.png"))
                window.close()
            }
            print("Native UI regression PASS; preview: \(output.path)/inbox-results.png")
            return 0
        } catch {
            fputs("Native UI regression FAILED: \(error)\n", stderr)
            return 1
        }
    }

    private static var frontPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    private static func saveViaMCP(path: URL, captureID: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("BeamhopMCP")
        process.arguments = ["--db", path.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                    "params": ["name": "save_result", "arguments": [
                                        "origin_capture_id": captureID, "agent": "codex", "session_id": "regression-1",
                                        "content": "已核对来源与投递：取消会恢复焦点，结论与原始 Capture 关联。"]]]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0a)
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.closeFile()
        let response = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              json["error"] == nil, let result = json["result"] as? [String: Any],
              result["isError"] as? Bool != true else {
            throw Failure(description: "external MCP save_result failed")
        }
        print("  ✓ real MCP subprocess saved a conclusion to the fixture database")
    }

    private static func launchFixture() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--focus-fixture"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func waitForApp(_ process: Process) throws -> NSRunningApplication {
        try wait("fixture app launches") {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.isFinishedLaunching == true
        }
        guard let app = NSRunningApplication(processIdentifier: process.processIdentifier) else {
            throw Failure(description: "fixture app not registered")
        }
        return app
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
        print("  ✓ \(message)")
    }

    private static func wait(_ message: String, timeout: TimeInterval = 3,
                             until condition: () -> Bool) throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { pump(seconds: 0.02) }
        guard condition() else {
            let windows = NSApp.windows.map { "\($0.title):visible=\($0.isVisible),key=\($0.isKeyWindow)" }
            throw Failure(description: "\(message); front=\(frontPID.map(String.init) ?? "nil") own=\(ProcessInfo.processInfo.processIdentifier) active=\(NSApp.isActive) windows=\(windows)")
        }
        print("  ✓ \(message)")
    }

    private static func pump(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01),
                                          inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }
}
#endif
