import AppKit
import SwiftUI
import BeamhopCore

/// Offscreen production views + synthetic rows only. Never activates a window, requests
/// permissions, reads configuration/Inbox or runs the real diagnostic collector.
enum TrialEngineeringSmoke {
    static func run(output: URL, chinese: Bool, dark: Bool) throws {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let build = BuildInfo.load()
        let rows: [DiagRow] = DiagnosticCheckID.allCases.map {
            DiagRow(id: $0, name: $0.rawValue, state: .warn,
                    detail: "Fixture detail: /Users/private/token https://private.invalid SECRET_NOTE",
                    fixTitle: nil, fix: nil)
        }
        let report = DiagnosticsService.report(rows: rows, build: build)
        let data = try report.jsonData()
        let json = String(decoding: data, as: UTF8.self)
        guard !["/Users/private", "private.invalid", "SECRET_NOTE", "Fixture detail"].contains(where: json.contains),
              data == (try report.jsonData()) else {
            throw NSError(domain: "TrialSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Privacy allowlist failed"])
        }
        let language = chinese ? "zh-Hans" : "en"
        let suffix = "\(language)-\(dark ? "dark" : "light")"
        try data.write(to: output.appendingPathComponent("fixture-report-\(suffix).json"), options: .atomic)
        try snapshot(DiagnosticsView(rows: rows, build: build, onExport: {}),
                     size: NSSize(width: 720, height: 760),
                     output: output.appendingPathComponent("diagnostics-\(suffix).png"), dark: dark)
        try snapshot(DiagnosticExportView(json: json, onCancel: {}, onSave: {}),
                     size: NSSize(width: 780, height: 650),
                     output: output.appendingPathComponent("export-\(suffix).png"), dark: dark)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front else {
            throw NSError(domain: "TrialSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Offscreen smoke changed foreground app"])
        }
        print("Trial engineering offscreen smoke PASS: \(suffix); no activation, private row details excluded")
    }

    private static func snapshot<V: View>(_ root: V, size: NSSize, output: URL, dark: Bool) throws {
        let view = NSHostingView(rootView: root
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light))
        view.setFrameSize(size)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "TrialSmoke", code: 3)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TrialSmoke", code: 4)
        }
        try data.write(to: output)
    }
}
