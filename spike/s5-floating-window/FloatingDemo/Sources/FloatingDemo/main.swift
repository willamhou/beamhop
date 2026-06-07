import Cocoa
import SwiftUI
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlay: NSWindow!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✦"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show overlay", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        overlay = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        overlay.title = "Beamhop floating demo"
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.isMovableByWindowBackground = true
        overlay.contentView = NSHostingView(rootView: OverlayView())
        overlay.center()

        // Register Cmd+Shift+Space global hotkey
        let hk = EventHotKeyID(signature: 0x53504B45, id: 1)
        let mods = UInt32(cmdKey | shiftKey)
        let key: UInt32 = 49 // space
        var ref: EventHotKeyRef?
        RegisterEventHotKey(key, mods, hk, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    @objc func toggle() {
        if overlay.isVisible { overlay.orderOut(nil) }
        else { overlay.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    @objc func quit() { NSApp.terminate(nil) }
}

struct OverlayView: View {
    @State var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("✦ Beamhop spike S5").font(.headline)
            Text("Press Cmd+Shift+Space to toggle me. Try in: full-screen Safari, full-screen VS Code, Stage Manager, dual-display.").font(.caption)
            TextField("Type to test keyboard focus...", text: $note)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Spacer()
                Text("Esc to dismiss").font(.caption2).foregroundColor(.secondary)
            }
        }.padding()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
