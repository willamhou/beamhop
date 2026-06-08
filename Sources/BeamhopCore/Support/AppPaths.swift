import Foundation

/// Filesystem locations. App support dir = `~/Library/Application Support/beamhop/` (spec §8.1).
public enum AppPaths {
    /// Overridable for tests (point at a temp dir).
    public static var overrideSupportDir: URL?

    public static var supportDir: URL {
        if let o = overrideSupportDir { return o }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("beamhop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var databaseURL: URL { supportDir.appendingPathComponent("inbox.sqlite") }
    public static var screenshotsDir: URL { supportDir.appendingPathComponent("screenshots", isDirectory: true) }
}
