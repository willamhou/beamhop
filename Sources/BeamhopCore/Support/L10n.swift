import Foundation

/// UI string localization seam (repo policy 2026-10-18: **English is the default language**).
///
/// Every user-facing string goes through `L10n.s("…")` (Foundation contexts) or a SwiftUI
/// `Text`/`Label`/`Button` string literal (auto-localized by the framework). With no
/// `Localizable.strings` match the key itself is returned — i.e. English.
///
/// Chinese ships as `packaging/lproj/zh-Hans.lproj/Localizable.strings`, which
/// `packaging/build-app.sh` copies into the app bundle's `Resources/zh-Hans.lproj/`.
/// The menu-bar Language submenu flips the per-app `AppleLanguages` override and
/// relaunches — Foundation + SwiftUI lookups then resolve zh-Hans (2026-10-19).
/// Interpolated strings use `L10n.f("Deliver (%@)", x)` so format keys can localize.
public enum L10n {
    public static func s(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// Format-style lookup for interpolated UI strings (keeps the strings-table key stable).
    public static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }
}
