import Foundation
import GRDB

/// Local usage vocabulary. No material, project/session name, path or error text.
public struct HopActivity: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started, copied, prepared, failed, interrupted, saved, restored, reused, recovered
    }
    public let kind: Kind
    public let id: String
    public let sourceDraftIDs: [String]
    public let readableFailure: Bool
    public init(_ kind: Kind, id: String, sourceDraftIDs: [String] = [], readableFailure: Bool = false) {
        self.kind = kind
        self.id = id
        self.sourceDraftIDs = sourceDraftIDs
        self.readableFailure = readableFailure
    }
}

extension EventStore {
    public func recordHop(_ activity: HopActivity, date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(activity), let detail = String(data: data, encoding: .utf8) else {
            return
        }
        record(name: Name.hopActivity, detail: detail, date: date)
    }
}

/// Attempts are identified by start events, never by per-material legacy delivery rows.
/// Events survive backup deletion, but are local/180-day-retained and may be unavailable
/// for old builds. A trial task count and task completion require human evidence.
public struct HopUsage {
    public internal(set) var attempts = 0
    public internal(set) var copied = 0
    public internal(set) var prepared = 0
    public internal(set) var failed = 0
    public internal(set) var interrupted = 0
    public var pending: Int { attempts - copied - prepared - failed - interrupted }
    public internal(set) var readableFailures = 0
    public internal(set) var pocketHandoffs = 0
    public internal(set) var savedDrafts = 0
    public internal(set) var reusedDrafts = 0
    public internal(set) var recoveredBackups = 0
    public internal(set) var returnedHandoffs = 0
    public internal(set) var retainedConclusions = 0
    public internal(set) var untrackedBackups = 0
    public internal(set) var ignoredEvents = 0

    static func read(_ db: GRDB.Database, since start: Int64, until end: Int64) throws -> HopUsage {
        var report = HopUsage()
        var starts: [String: (Int64, HopActivity)] = [:]
        var outcomes: [String: HopActivity] = [:]
        var saved = Set<String>()
        var reused = Set<String>()
        // rowid breaks same-millisecond ties by persisted insertion order, not random ULID suffix.
        for row in try Row.fetchAll(
            db, sql: "SELECT ts, detail FROM events WHERE name = ? AND ts <= ? ORDER BY ts, rowid",
            arguments: [EventStore.Name.hopActivity, end])
        {
            let ts: Int64 = row["ts"]
            guard let detail: String = row["detail"], let data = detail.data(using: .utf8),
                let event = try? JSONDecoder().decode(HopActivity.self, from: data), !event.id.isEmpty
            else {
                if ts >= start { report.ignoredEvents += 1 }
                continue
            }
            switch event.kind {
            case .started:
                if starts[event.id] == nil { starts[event.id] = (ts, event) }
            case .copied, .prepared, .failed, .interrupted: outcomes[event.id] = event
            case .saved: if ts >= start { saved.insert(event.id) }
            case .restored, .reused: if ts >= start { reused.insert(event.id) }
            case .recovered: if ts >= start { report.recoveredBackups += 1 }
            }
        }
        for (id, entry) in starts where entry.0 >= start {
            report.attempts += 1
            if !entry.1.sourceDraftIDs.isEmpty {
                report.pocketHandoffs += 1
                if outcomes[id]?.kind == .copied || outcomes[id]?.kind == .prepared {
                    reused.formUnion(entry.1.sourceDraftIDs)
                }
            }
            switch outcomes[id]?.kind {
            case .copied: report.copied += 1
            case .prepared: report.prepared += 1
            case .failed:
                report.failed += 1
                if outcomes[id]?.readableFailure == true { report.readableFailures += 1 }
            case .interrupted: report.interrupted += 1
            default: break
            }
        }
        report.savedDrafts = saved.count
        report.reusedDrafts = reused.count
        let ids = try String.fetchAll(db, sql: "SELECT id FROM hop_records")
        report.untrackedBackups = ids.filter { starts[$0] == nil }.count
        let results = try Row.fetchOne(
            db,
            sql:
                "SELECT COUNT(*) AS n, COUNT(DISTINCT handoff_id) AS origins FROM handoff_results WHERE created_at >= ? AND created_at <= ?",
            arguments: [start, end])!
        report.retainedConclusions = results["n"]
        report.returnedHandoffs = results["origins"]
        return report
    }
}
