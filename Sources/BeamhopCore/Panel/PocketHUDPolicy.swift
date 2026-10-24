import Foundation

/// Pure visibility/geometry policy for the bottom-right Pocket HUD chip. The app target
/// renders the chip; the rules live here so both XCTest and the CLT SelfTest runner can
/// cover them (owner UX pass 2026-10-24: hide-when-empty and idle-fade became settings).
public enum PocketHUDPolicy {
    public static let defaultsKeyHideWhenEmpty = "pocketHUD.hideWhenEmpty"
    public static let defaultsKeyIdleFade = "pocketHUD.idleFade"
    /// Defaults registered by the app on launch: both behaviors ship enabled.
    public static let registeredDefaults: [String: Any] = [
        defaultsKeyHideWhenEmpty: true,
        defaultsKeyIdleFade: true,
    ]

    /// The chip occupies screen space only while the stack (held items + non-empty draft)
    /// is non-empty — unless the user switched "hide when empty" off, in which case it
    /// stays visible as a permanent launcher (showing Pocket · 0).
    public static func isVisible(count: Int, hideWhenEmpty: Bool) -> Bool {
        count > 0 || !hideWhenEmpty
    }

    /// Idle opacity: faint unless the fade setting is off or the mouse is over the chip.
    public static func opacity(idleFade: Bool, hovered: Bool) -> Double {
        (idleFade && !hovered) ? 0.55 : 1.0
    }

    /// Parse a persisted "x,y" origin string; nil when absent or malformed.
    public static func parseOrigin(_ raw: String?) -> CGPoint? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    public static func formatOrigin(_ origin: CGPoint) -> String { "\(origin.x),\(origin.y)" }

    /// Clamp a panel origin into `visibleFrame` so a stale or off-screen persisted point
    /// (display rearrangement, resolution change, corrupted string) can never strand the
    /// chip outside the reachable screen.
    public static func clampedOrigin(_ origin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let minX = visibleFrame.minX
        let minY = visibleFrame.minY
        let x = min(max(origin.x, minX), max(minX, visibleFrame.maxX - panelSize.width))
        let y = min(max(origin.y, minY), max(minY, visibleFrame.maxY - panelSize.height))
        return CGPoint(x: x, y: y)
    }
}
