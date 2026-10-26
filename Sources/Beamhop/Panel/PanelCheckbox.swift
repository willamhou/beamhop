import AppKit
import SwiftUI
import BeamhopCore

private final class PanelCheckboxButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}

/// SwiftUI Toggle is not exposed in the nonactivating panel's accessibility tree
/// on supported macOS runtimes. Keep the real checkbox and its binding native.
struct PanelCheckbox: NSViewRepresentable {
    let title: String
    let identifier: String
    @Binding var isOn: Bool

    final class Coordinator: NSObject {
        var binding: Binding<Bool>
        init(_ binding: Binding<Bool>) { self.binding = binding }
        @objc func changed(_ sender: NSButton) { binding.wrappedValue = sender.state == .on }
    }
    func makeCoordinator() -> Coordinator { Coordinator($isOn) }
    func makeNSView(context: Context) -> NSButton {
        let button = PanelCheckboxButton(checkboxWithTitle: "", target: context.coordinator,
                                         action: #selector(Coordinator.changed(_:)))
        button.setAccessibilityElement(true)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.binding = $isOn
        button.title = L10n.s(title)
        button.state = isOn ? .on : .off
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(L10n.s(title))
        button.setAccessibilityIdentifier(identifier)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: nsView.fittingSize.width, height: 22)
    }
}
