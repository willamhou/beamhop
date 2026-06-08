import Foundation
import GRDB

/// Read-only capture access for the MCP server process (works on a read-only DatabaseQueue).
public final class CaptureReader {
    private let queue: DatabaseQueue
    public init(_ queue: DatabaseQueue) { self.queue = queue }

    /// Open read-only from a DB path (throws DatabaseError.fileNotFound if missing).
    public static func open(path: URL) throws -> CaptureReader {
        CaptureReader(try Database.openReadOnly(path: path))
    }

    public func latest() throws -> Capture? {
        try queue.read { db in
            try Capture.filter(sql: "deleted_at IS NULL").order(sql: "created_at DESC").fetchOne(db)
        }
    }

    public func fetch(id: String) throws -> Capture? {
        try queue.read { db in
            try Capture.filter(sql: "id = ? AND deleted_at IS NULL", arguments: [id]).fetchOne(db)
        }
    }

    /// Encode a Capture as pretty JSON for an agent to consume.
    public static func renderJSON(_ capture: Capture) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(capture), let s = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"encode failed\"}"
        }
        return s
    }
}
