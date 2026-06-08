import Foundation

/// App + OS version helpers (feed Capture provenance — spec §12.1).
public enum Version {
    /// Beamhop's own version. From Info.plist when bundled; falls back to a dev string under SwiftPM.
    public static var beamhop: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0-dev"
    }

    public static var os: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
