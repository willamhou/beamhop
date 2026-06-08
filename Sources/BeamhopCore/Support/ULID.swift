import Foundation

/// Full ULID (128-bit: 48-bit ms timestamp + 80-bit randomness), Crockford base32, 26 chars.
/// Used as the Capture primary key (`cap_<ulid>`). The UI shows only a short prefix
/// (`shortPrefix`), but the DB key is the full ULID to avoid collisions — Week 1 codex review
/// flagged `cap_<6>` (~1.07e9 space) as collision-prone.
public enum ULID {
    private static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a 26-char ULID string.
    public static func generate(date: Date = Date()) -> String {
        var chars = [Character](repeating: "0", count: 26)

        // 48-bit timestamp (ms), encoded in the first 10 base32 chars (high bits first).
        var ms = UInt64(max(0, date.timeIntervalSince1970) * 1000)
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = crockford[Int(ms & 0x1F)]
            ms >>= 5
        }

        // 80-bit randomness in the remaining 16 base32 chars.
        for i in 10..<26 {
            chars[i] = crockford[Int.random(in: 0..<32)]
        }
        return String(chars)
    }

    /// A capture id: `cap_<26-char ulid>`.
    public static func captureID(date: Date = Date()) -> String {
        "cap_" + generate(date: date)
    }

    /// Short, human-facing prefix of a capture id (e.g. for compact UI labels).
    /// `cap_01J9Z…` -> `cap_01J9Z6` style (prefix + first 6 ulid chars).
    public static func shortPrefix(of captureID: String, length: Int = 6) -> String {
        guard captureID.hasPrefix("cap_") else { return String(captureID.prefix(length)) }
        let ulid = captureID.dropFirst(4)
        return "cap_" + ulid.prefix(length)
    }
}
