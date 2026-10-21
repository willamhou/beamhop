import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BeamhopCore

/// Holds one immutable preview. The exact preview bytes are written only after Save confirmation.
final class DiagnosticExportController {
    private let report: DiagnosticReport
    private var window: NSWindow?
    init(report: DiagnosticReport) { self.report = report }
    func close() { window?.close() }

    func show() {
        guard let data = try? report.jsonData(), let json = String(data: data, encoding: .utf8) else { return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = L10n.s("Diagnostic export preview")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: DiagnosticExportView(json: json,
            onCancel: { [weak w] in w?.close() },
            onSave: { [weak self] in self?.save(data) }))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    private func save(_ data: Data) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "beamhop-diagnostics.json"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                window.close()
            } catch {
                let alert = NSAlert()
                // Never put an NSError with a local path or private text into this UI/report.
                alert.messageText = L10n.s("Could not save the report. Choose another location.")
                alert.beginSheetModal(for: window)
            }
        }
    }
}

struct DiagnosticExportView: View {
    let json: String
    let onCancel: () -> Void
    let onSave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review before saving").font(.headline)
            Text("Includes build, macOS version and status codes only. No logs, local paths, URLs, capture text, notes, sessions or credentials. Nothing is uploaded.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: json).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.background(Color(nsColor: .textBackgroundColor))
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save report…", action: onSave).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(minWidth: 620, minHeight: 450)
    }
}
