import Foundation

/// Apps we refuse to capture from (spec §6.6 / §11): password managers, banking, etc.
/// Captures from these are rejected with a user-facing reason.
public enum AppBlacklist {
    public static let bundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.lastpass.LastPass",
        "com.lastpass.lastpassmacdesktop",
        "in.sinew.Walletx",            // Enpass
        "com.sinew.Walletx",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.apple.keychainaccess",
    ]

    public static func isBlocked(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}
