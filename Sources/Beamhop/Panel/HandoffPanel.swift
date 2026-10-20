import AppKit
import SwiftUI

/// Takes keyboard focus without activating Beamhop or becoming a document window.
final class HandoffPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onShortcut: ((String) -> Bool)?
    var onReturn: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if modifiers == .command, let key = event.charactersIgnoringModifiers,
           onShortcut?(key) == true { return true }
        if modifiers.isEmpty, event.keyCode == 53 {
            onEscape?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }
        if event.keyCode == 36, let onReturn { onReturn(); return }
        super.keyDown(with: event)
    }
}

/// SwiftUI reports its natural size as notes/errors appear. Resizing keeps the panel's
/// top edge (capture) or bottom edge (corner shelf) fixed instead of moving the user's target.
struct PanelSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear
                .onAppear { onChange(geometry.size) }
                .onChange(of: geometry.size) { _, size in onChange(size) }
        })
    }
}

extension HandoffPanel {
    func fitContent(_ size: CGSize, keepingBottom: Bool = false) {
        guard size.width > 0, size.height > 0 else { return }
        let oldFrame = frame
        var next = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        next.origin = NSPoint(x: oldFrame.minX,
                              y: keepingBottom ? oldFrame.minY : oldFrame.maxY - next.height)
        if let screen = screen ?? NSScreen.main {
            let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            next.origin.x = min(max(next.minX, safe.minX), max(safe.minX, safe.maxX - next.width))
            next.origin.y = min(max(next.minY, safe.minY), max(safe.minY, safe.maxY - next.height))
        }
        if abs(frame.width - next.width) > 0.5 || abs(frame.height - next.height) > 0.5 {
            setFrame(next, display: true)
        }
    }
}
