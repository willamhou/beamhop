import AppKit
import BeamhopCore
import SwiftUI

/// Native controls retain their accessibility identities in nonactivating panels.
struct TaskChoicePicker: NSViewRepresentable {
    let tasks: [HopTask]
    let emptyTitle: String
    let identifier: String
    @Binding var selectedID: String?

    final class Coordinator: NSObject {
        var binding: Binding<String?>
        var ids: [String?] = []
        init(_ binding: Binding<String?>) { self.binding = binding }
        @objc func choose(_ sender: NSPopUpButton) {
            guard ids.indices.contains(sender.indexOfSelectedItem) else { return }
            binding.wrappedValue = ids[sender.indexOfSelectedItem]
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator($selectedID) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityElement(true)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.binding = $selectedID
        context.coordinator.ids = [nil] + tasks.map { Optional($0.id) }
        let titles = [L10n.s(emptyTitle)] + tasks.map(\.displayLabel)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: context.coordinator.ids.firstIndex(of: selectedID) ?? 0)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.lineBreakMode = .byTruncatingMiddle
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(L10n.s("Task"))
        button.setAccessibilityIdentifier(identifier)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context)
        -> CGSize?
    {
        CGSize(width: min(proposal.width ?? 360, nsView.fittingSize.width), height: 22)
    }
}

struct RelayTextEditor: NSViewRepresentable {
    @Binding var text: String
    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        init(_ binding: Binding<String>) { self.binding = binding }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            binding.wrappedValue = editor.string
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator($text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 70))
        editor.minSize = NSSize(width: 0, height: 70)
        editor.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        editor.isRichText = false
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.font = .systemFont(ofSize: 12)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(L10n.s("Relay context"))
        editor.setAccessibilityIdentifier("capture.relay-text")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.binding = $text
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = context.environment.isEnabled
    }
}
