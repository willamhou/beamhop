import AppKit
import SwiftUI
import BeamhopCore

/// Bottom-right pocket chip (2026-10-19 UI pass): 「先留着」 previously vanished without a
/// trace — the user couldn't see the hold stack existed. While the pocket holds anything,
/// this small capsule sits at the screen's bottom-right: 「📥 口袋 · N  ⌘⇧P」. Click opens the
/// full Pocket window; it hides itself the moment the stack is empty. Hidden, never destroyed.
final class PocketHUDController {
    private var panel: NSPanel?
    private let model = PocketHUDModel()
    var onOpen: (() -> Void)?

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: PocketHUDView(model: model) { [weak self] in
            self?.onOpen?()
        })
        return p
    }

    /// count > 0 → show at bottom-right; 0 → hide. Idempotent, safe from any thread.
    func update(count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.count = count
            guard count > 0 else { self.panel?.orderOut(nil); return }
            if self.panel == nil { self.panel = self.makePanel() }
            guard let panel = self.panel else { return }
            let sf = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: sf.maxX - size.width - 16,
                                         y: sf.minY + 16))
            panel.orderFrontRegardless()
        }
    }
}

final class PocketHUDModel: ObservableObject {
    @Published var count: Int = 0
}

private struct PocketHUDView: View {
    @ObservedObject var model: PocketHUDModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 12))
                Text(L10n.f("口袋 · %lld", Int64(model.count)))
                    .font(.callout.weight(.medium))
                Text("⌘⇧P")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
