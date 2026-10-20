import AppKit
import BeamhopCore

/// Probes this machine for the delivery targets that ACTUALLY exist, then defers to
/// TargetAvailability.resolve for the ordered panel list. ChatGPT Desktop has shipped
/// under more than one bundle id (com.openai.chatgpt / com.openai.codex) — accept either.
enum TargetDetector {
    static func availableTargets() -> [DeliveryTarget] {
        let workspace = NSWorkspace.shared
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let hasClaudeCLI = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                            "\(home)/.local/bin/claude"].contains { fm.fileExists(atPath: $0) }
            || fm.fileExists(atPath: "\(home)/.claude")   // CLI leaves this config dir
        let hasChatGPT = ChatGPTDelivery.bundleIDs.contains {
            workspace.urlForApplication(withBundleIdentifier: $0) != nil
        }
        let hasKimi = workspace.urlForApplication(withBundleIdentifier: "com.moonshot.kimichat") != nil

        return TargetAvailability.resolve(hasClaudeCLI: hasClaudeCLI,
                                          hasChatGPTApp: hasChatGPT,
                                          hasKimiApp: hasKimi)
    }
}
