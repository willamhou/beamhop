import AppKit
import SwiftUI
import BeamhopCore

/// NSMenu supplies native menu tracking. The visible label stays a regular SwiftUI
/// button: SwiftUI.Menu on macOS flattens multiline labels and drops the receiver detail.
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
        menu.addItem(.sectionHeader(title: L10n.s("Applications")))
        for shortcut in PanelShortcut.allCases {
            guard let target = shortcut.target, model.visibleTargets.contains(target) else { continue }
            add(target.displayName, selected: model.workName.isEmpty && model.selectedTarget == target,
                shortcut: shortcut.rawValue) { model.chooseTool(target) }
        }
        menu.addItem(.separator())
        add(L10n.s("Remember with a name…"), enabled: model.selectedTarget != nil, action: onName)
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

struct DestinationMenuAnchor: NSViewRepresentable {
    let presenter: DestinationMenuPresenter
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        presenter.anchor = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { presenter.anchor = view }
}
