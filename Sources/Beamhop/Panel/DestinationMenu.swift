import AppKit
import SwiftUI
import BeamhopCore

/// NSMenu supplies native menu tracking. A native button handles input and
/// accessibility while SwiftUI renders the full multiline destination label.
final class DestinationMenuPresenter: NSObject {
    weak var anchor: NSView?
    private var actions: [() -> Void] = []
    private var activeMenu: NSMenu?

    func show(model: CapturePanelModel, onName: @escaping () -> Void) {
        guard let anchor else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        actions = []
        func add(_ title: String, selected: Bool = false, enabled: Bool = true,
                 shortcut: String = "", action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(chooseDestination(_:)), keyEquivalent: shortcut)
            item.target = self
            item.tag = actions.count
            item.isEnabled = enabled
            item.state = selected ? .on : .off
            if !shortcut.isEmpty { item.keyEquivalentModifierMask = .command }
            actions.append(action)
            menu.addItem(item)
        }
        if !model.availableWorks.isEmpty {
            menu.addItem(.sectionHeader(title: L10n.s("Recent work")))
            for work in model.availableWorks {
                add("\(work.name) · \(work.boundTarget.displayName)",
                    selected: model.boundWork?.id == work.id,
                    enabled: model.visibleTargets.contains(work.boundTarget)) { model.chooseWork(work) }
            }
            menu.addItem(.separator())
        }
        if !model.savedRoutes.isEmpty {
            menu.addItem(.sectionHeader(title: L10n.s("Recent destinations")))
            for route in model.savedRoutes {
                add([route.project, route.target?.displayName ?? L10n.s("Inbox"), route.sessionLabel]
                    .filter { !$0.isEmpty }.joined(separator: " · "), selected: model.snapshot.route == route) {
                    model.chooseRoute(route)
                }
            }
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: L10n.s("Applications")))
        for shortcut in PanelShortcut.allCases {
            guard let target = shortcut.target, model.visibleTargets.contains(target) else { continue }
            add(target.displayName, selected: model.workName.isEmpty && model.selectedTarget == target,
                shortcut: shortcut.rawValue) { model.chooseTool(target) }
        }
        menu.addItem(.separator())
        add(L10n.s("New session…"), enabled: model.selectedTarget != nil) {
            model.creatingProject = false; model.isCreating = true
        }
        add(L10n.s("New project…"), action: onName)
        add(L10n.s("Save to Inbox only"), shortcut: "0") { model.chooseTool(nil) }
        activeMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
        activeMenu = nil
    }

    @objc private func chooseDestination(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

/// Keep a concrete AppKit control for keyboard focus and accessibility. The
/// SwiftUI label above it does not intercept input or duplicate the accessible name.
struct DestinationButton: NSViewRepresentable {
    let presenter: DestinationMenuPresenter
    let model: CapturePanelModel
    let onName: () -> Void

    func makeNSView(context: Context) -> DestinationNativeButton {
        let button = DestinationNativeButton()
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityElement(true)
        button.setAccessibilityIdentifier("capture.destination")
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: DestinationNativeButton, context: Context) {
        presenter.anchor = button
        button.onPress = { presenter.show(model: model, onName: onName) }
        let detail = model.unavailableTarget != nil
            ? L10n.s("Unavailable · choose another destination or hold for later")
            : model.selectedTarget?.handoffDetail ?? L10n.s("Keep a local record")
        let receiver = (model.selectedTarget ?? model.unavailableTarget)?.displayName
        button.setAccessibilityLabel(([L10n.f("Destination: %@", model.destinationTitle)]
            + (receiver.map { [$0] } ?? []) + [detail]).joined(separator: ". "))
    }
}

final class DestinationNativeButton: NSButton {
    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(openDestinations(_:))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func openDestinations(_ sender: Any?) { onPress?() }
}
