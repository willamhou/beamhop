import AppKit
import SwiftUI
import BeamhopCore

/// Bottom-right pocket chip (2026-10-19 UI pass, behavior fixed 2026-10-24): 「先留着」
/// previously vanished without a trace — the chip exists so the user can see the hold stack.
/// Rules (owner-requested UI pass 2026-10-24):
///   - VISIBLE ONLY WHEN NON-EMPTY: count == 0 → the chip orders out and never occupies
///     screen space (the implementation regressed to always-show; the doc comment always
///     promised hide-when-empty).
///   - DRAGGABLE: movable by window background; the dragged position persists across
///     launches (UserDefaults), clamped to the visible frame so it can never be lost.
///   - IDLE-FAINT: fades to 55% opacity until the mouse enters, so it stops drawing the eye
///     while still signalling the stack exists. Click still opens the full Pocket window;
///     the ⌘⇧P shortcut works whether or not the chip is visible.
final class PocketHUDController {
    private var panel: NSPanel?
    private let model = PocketHUDModel()
    var onOpen: (() -> Void)?

    private static let originKey = "pocketHUD.origin"

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true   // drag anywhere on the chip (not just title bar)
        p.backgroundColor = .clear
        p.hasShadow = true
        let hosting = PocketHUDHostingView(rootView: PocketHUDView(model: model) { [weak self] in
            self?.onOpen?()
        })
        p.contentView = hosting
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak p] _ in
            guard let origin = p?.frame.origin else { return }
            UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
        }
        return p
    }

    /// count > 0 → show (restoring the user's dragged position, default bottom-right);
    /// count == 0 → hide. Idempotent, safe from any thread. `hasRecords` is accepted for
    /// call-site compatibility; visibility is deliberately count-driven (drafts/held items).
    func update(count: Int, hasRecords: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.count = max(0, count)
            guard self.model.count > 0 else {
                self.panel?.orderOut(nil)   // empty stack: never occupy the screen
                return
            }
            if self.panel == nil { self.panel = self.makePanel() }
            guard let panel = self.panel else { return }
            if let origin = Self.savedOrigin(panelSize: panel.frame.size) {
                panel.setFrameOrigin(origin)
            } else {
                let sf = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
                panel.setFrameOrigin(NSPoint(x: sf.maxX - panel.frame.width - 16,
                                             y: sf.minY + 16))
            }
            panel.orderFrontRegardless()
        }
    }

    /// Persisted drag position, clamped into the current visible frame so a stale or
    /// off-screen point (display rearrangement, resolution change) can't strand the chip.
    private static func savedOrigin(panelSize: CGSize) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: originKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, let sf = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame
        else { return nil }
        let x = min(max(parts[0], sf.minX), max(sf.minX, sf.maxX - panelSize.width))
        let y = min(max(parts[1], sf.minY), max(sf.minY, sf.maxY - panelSize.height))
        return NSPoint(x: x, y: y)
    }
}

/// Without this, SwiftUI content swallows mouse-down and the panel's movable-by-background
/// never engages; with it, a press-drag moves the chip and a plain click still fires the button.
private final class PocketHUDHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class PocketHUDModel: ObservableObject {
    @Published var count: Int = 0
}

private struct PocketHUDView: View {
    @ObservedObject var model: PocketHUDModel
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 12))
                Text(L10n.f("Pocket · %lld", Int64(model.count)))
                    .font(.callout.weight(.medium))
                Text("⌘⇧P")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1.0 : 0.55)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { hovered = hovering }
        }
    }
}
