import AppKit
import Carbon
import SwiftUI

private let hotKeySignature: OSType = 0x42484F50 // BHOP

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✦"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show overlay", action: #selector(toggle), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Beamhop S5"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: DemoView(onDismiss: { [weak self] in self?.hide() }))
        window = panel
        registerHotKey()
    }

    private func registerHotKey() {
        var identifier = EventHotKeyID(signature: hotKeySignature, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), identifier,
                            GetApplicationEventTarget(), 0, &hotKey)
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer, let event else { return noErr }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == hotKeySignature, identifier.id == 1 else { return noErr }
            let owner = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { owner.toggle() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @objc private func toggle() {
        guard let window else { return }
        window.isVisible ? hide() : show()
    }

    private func show() {
        guard let window else { return }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let x = screen.visibleFrame.midX - window.frame.width / 2
            let y = screen.visibleFrame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hide() { window?.orderOut(nil) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct DemoView: View {
    @State private var text = ""
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Beamhop floating-window probe").font(.headline)
            Text("Type a unique phrase, then verify the hotkey can hide and reshow this panel in every scenario.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Keyboard focus test", text: $text).textFieldStyle(.roundedBorder)
            HStack {
                Text("Focus: \(text.isEmpty ? "not proven" : "received input")").font(.caption)
                Spacer()
                Button("Dismiss", action: onDismiss).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

