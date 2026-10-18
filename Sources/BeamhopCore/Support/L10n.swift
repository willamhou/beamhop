import Foundation

/// UI string localization seam (repo policy 2026-10-18: **English is the default language**).
///
/// Every user-facing string goes through `L10n.s("…")` (Foundation contexts) or a SwiftUI
/// `Text`/`Label`/`Button` string literal (auto-localized by the framework). With no
/// `Localizable.strings` in the app bundle the key itself is returned — i.e. English.
///
/// Chinese translations are ARCHIVED (not shipped) at
/// `packaging/lproj/zh-Hans.lproj/Localizable.strings`; to ship Chinese, copy that file
/// into the app bundle's `zh-Hans.lproj/` (see PROGRESS §7.C).
public enum L10n {
    public static func s(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
