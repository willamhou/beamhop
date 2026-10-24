import AppKit
import SwiftUI
import BeamhopCore

/// Bottom-right pocket chip (2026-10-19 UI pass; behavior/UX pass 2026-10-24): 「先留着」
/// previously vanished without a trace — the chip exists so the user can see the hold stack.
/// Current rules (owner-driven, both toggleable from the menu-bar "Pocket chip" submenu):
///   - HIDE WHEN EMPTY (default ON): count == 0 → the chip orders out and never occupies
///     screen space.
///   - FADE WHEN IDLE (default ON): 55% opacity until the mouse enters, so it stops drawing
///     the eye while still signalling the stack exists.
///   - DRAGGABLE: press-drag anywhere on the chip moves the panel (local leftMouseDragged
///     monitor — SwiftUI Buttons swallow AppKit background-drag, so isMovableByWindowBackground
///     never engaged in practice, owner-verified 2026-10-24). The dragged position persists
///     across launches (UserDefaults), clamped to the visible frame so it can never be lost.
///   - Click opens the full Pocket window; ⌘⇧P works whether or not the chip is visible.
final class PocketHUDController {
    static let hideWhenEmptyKey = "pocketHUD.hideWhenEmpty"
    static let idleFadeKey = "pocketHUD.idleFade"
    private static let originKey = "pocketHUD.origin"

    private var panel: NSPanel?
    private let model = PocketHUDModel()
    private var lastCount = 0
    private var defaultsObserver: NSObjectProtocol?
    private var dragMonitor: Any?
    var onOpen: (() -> Void)?

    static var hideWhenEmptyEnabled: Bool { UserDefaults.standard.bool(forKey: hideWhenEmptyKey) }
    static var idleFadeEnabled: Bool { UserDefaults.standard.bool(forKey: idleFadeKey) }

    init() {
        UserDefaults.standard.register(defaults: [
            Self.hideWhenEmptyKey: true,
            Self.idleFadeKey: true,
        ])
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.model.idleFade = Self.idleFadeEnabled
            self.applyVisibility()
        }
        // Press-drag moves the chip. A LOCAL monitor is enough: drag events on our own panel
        // are delivered to our app even when it is not the active app (nonactivating panel).
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            var origin = panel.frame.origin
            origin.x += event.deltaX
            origin.y -= event.deltaY   // AppKit origin is bottom-left; event deltas are not
            panel.setFrameOrigin(origin)
            return event
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: PocketHUDView(model: model) { [weak self] in
            self?.onOpen?()
        })
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak p] _ in
            guard let origin = p?.frame.origin else { return }
            UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
        }
        return p
    }

    /// count > 0 → show (restoring the user's dragged position, default bottom-right);
    /// count == 0 → hide unless "hide when empty" is switched off. Idempotent, thread-safe.
    /// `hasRecords` is accepted for call-site compatibility; visibility is count-driven.
    func update(count: Int, hasRecords: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastCount = max(0, count)
            self.model.count = self.lastCount
            self.model.idleFade = Self.idleFadeEnabled
            self.applyVisibility()
        }
    }

    private func applyVisibility() {
        guard lastCount > 0 || !Self.hideWhenEmptyEnabled else {
            panel?.orderOut(nil)   // empty stack (per setting): never occupy the screen
            return
        }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        if let origin = Self.savedOrigin(panelSize: panel.frame.size) {
            panel.setFrameOrigin(origin)
        } else {
            let sf = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
            panel.setFrameOrigin(NSPoint(x: sf.maxX - panel.frame.width - 16,
                                         y: sf.minY + 16))
        }
        panel.orderFrontRegardless()
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

final class PocketHUDModel: ObservableObject {
    @Published var count: Int = 0
    @Published var idleFade: Bool = true
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
        .opacity(model.idleFade && !hovered ? 0.55 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { hovered = hovering }
        }
    }
}
