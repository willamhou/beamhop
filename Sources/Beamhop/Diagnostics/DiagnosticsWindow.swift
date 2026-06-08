import AppKit
import SwiftUI

/// Independent diagnostics window (spec §12.2 / §9.4). isReleasedWhenClosed = false so it can be
/// reopened from the menu without crashing (Week 0 S5 lesson).
final class DiagnosticsWindowController {
    private var window: NSWindow?
    private let service: () -> DiagnosticsService

    init(service: @escaping () -> DiagnosticsService) { self.service = service }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Beamhop 诊断"
            w.isReleasedWhenClosed = false       // S5: hide, don't destroy
            w.center()
            window = w
        }
        // rebuild content each show so statuses are fresh
        window?.contentView = NSHostingView(rootView: DiagnosticsView(rows: service().rows()))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DiagnosticsView: View {
    let rows: [DiagRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permission Diagnostics").font(.headline).padding([.top, .horizontal], 16)
            Text("80% 的「它不工作」都是下面某项失效 —— 一键修。")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.state.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).fontWeight(.medium)
                                Text(row.detail).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if let title = row.fixTitle, let fix = row.fix {
                                Button(title) { fix() }
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}
