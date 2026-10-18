import Foundation

/// W3-4 duplicate-press guard (spec §11): the user double-tapping the hotkey on the SAME
/// window within 500ms must not create a second capture row. Pure decision logic — the
/// caller supplies the clock so tests can step time deterministically.
public struct DuplicateGate {
    public var window: TimeInterval

    private var last: (bundleID: String, title: String?, at: Date)?

    public init(window: TimeInterval = 0.5) {
        self.window = window
    }

    /// Records this press and reports whether it is a duplicate of the immediately preceding
    /// press on the same (bundleID, windowTitle).
    public mutating func isDuplicate(bundleID: String, title: String?, at: Date = Date()) -> Bool {
        defer { last = (bundleID, title, at) }
        if let prev = last,
           at.timeIntervalSince(prev.at) < window,
           prev.bundleID == bundleID,
           prev.title == title {
            return true
        }
        return false
    }

    /// Drop all memory (e.g. after tests, or a fresh capture session).
    public mutating func reset() {
        last = nil
    }
}
