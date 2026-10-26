import Foundation
import GRDB

/// Aggregates the dogfood gate metrics (evolution-decisions §3) from the local DB:
/// press frequency and outcomes (`events`), panel P95 (`events` panel_shown ms=),
/// delivery success / readable-failure coverage (`deliveries`), Inbox accumulation
/// and engagement (`captures` + `events`).
///
/// The window is bounded on both ends. Inbox total and untracked retained backups
/// are cumulative. Transport rows can overlap Hop attempts; never add their totals.
public struct DogfoodReport {
    public let hops: HopUsage
    public let days: Int
    public let windowStartMs: Int64

    // Presses (⌘⇧Space outcomes)
    public let capturedCount: Int
    public let duplicateCount: Int
    public let rejectedCount: Int
    public var pressCount: Int { capturedCount + duplicateCount + rejectedCount }
    public var pressesPerDay: Double { days > 0 ? Double(pressCount) / Double(days) : 0 }
    /// Per-day press counts ("2026-10-18" → n), oldest first.
    public let perDay: [(day: String, presses: Int)]

    // Panel latency
    public let panelP95ms: Int?
    public let panelCount: Int

    // Legacy transport rows, which can include per-material rows for ordinary Hop.
    // Their denominator is not a task count or a whole-product handoff count.
    public let attempts: Int
    public let chosenTargetFailures: Int
    public var successRate: Double? { attempts > 0 ? Double(attempts - chosenTargetFailures) / Double(attempts) : nil }
    /// Failed chosen-target attempts that carry a non-empty error_message.
    public let readableFailures: Int
    public var readableFailureCoverage: Double? {
        chosenTargetFailures > 0 ? Double(readableFailures) / Double(chosenTargetFailures) : nil
    }
    public let avgDeliveryMs: Int?
    public let avgCaptureMs: Int?

    // Inbox
    public let inboxTotalCaptures: Int
    public let inboxOpenedCount: Int
    public var inboxVisitsPerWeek: Double { Double(inboxOpenedCount) * 7.0 / Double(max(1, days)) }
    public let searchCount: Int
    public let viewedCount: Int
    public let redeliverCount: Int

    public enum Invalid: Error { case days }
    public static func generate(db: Database, days: Int = 14, now: Date = Date()) throws -> DogfoodReport {
        try generate(queue: db.queue, days: days, now: now)
    }
    /// Reporting never creates, repairs or migrates the user's Inbox.
    public static func generate(path: URL, days: Int = 14, now: Date = Date()) throws -> DogfoodReport {
        try generate(queue: Database.openReadOnly(path: path), days: days, now: now)
    }
    private static func generate(queue: DatabaseQueue, days: Int, now: Date) throws -> DogfoodReport {
        guard (1...180).contains(days) else { throw Invalid.days }
        let end = Int64(now.timeIntervalSince1970 * 1000)
        let windowStart = end - Int64(days) * 24 * 3600 * 1000

        // Press outcomes in-window, grouped by name.
        var byName: [String: Int] = [:]
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT name, COUNT(*) AS n FROM events
                WHERE ts >= ? AND ts <= ? AND name IN (?, ?, ?)
                GROUP BY name
                """, arguments: [windowStart, end, EventStore.Name.captureCompleted,
                                 EventStore.Name.captureDuplicate, EventStore.Name.captureRejected])
            for r in rows { byName[r["name"]] = r["n"] }
        }

        let perDayRows: [(String, Int)] = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT date(ts / 1000, 'unixepoch', 'localtime') AS d, COUNT(*) AS n
                FROM events
                WHERE ts >= ? AND ts <= ? AND name IN (?, ?, ?)
                GROUP BY d ORDER BY d
                """, arguments: [windowStart, end, EventStore.Name.captureCompleted,
                                 EventStore.Name.captureDuplicate, EventStore.Name.captureRejected])
            .map { ($0["d"], $0["n"]) }
        }

        // Panel latencies: details are "ms=<int>" (column nullable).
        let panelMs: [Int] = try queue.read { db in
            let details: [String?] = try String?.fetchAll(db, sql: "SELECT detail FROM events WHERE ts >= ? AND ts <= ? AND name = ?",
                                                          arguments: [windowStart, end, EventStore.Name.panelShown])
            return details.compactMap { d in
                guard let d, d.hasPrefix("ms="), let v = Int(d.dropFirst(3)) else { return nil }
                return v
            }
        }

        // Deliveries in-window: chosen-target attempts exclude clipboard rows (those are either
        // fallbacks, explicit picks, or the ⌘⇧V emergency channel — none count as gate attempts).
        // COALESCE/CAST: SUM is NULL on zero rows and AVG returns a Double.
        let (attempts, failures, readable, avgMs) = try queue.read { db -> (Int, Int, Int, Int?) in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) AS attempts,
                    COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failures,
                    COALESCE(SUM(CASE WHEN status = 'failed' AND error_message IS NOT NULL
                                    AND error_message != '' THEN 1 ELSE 0 END), 0) AS readable,
                    CAST(AVG(duration_ms) AS INTEGER) AS avg_ms
                FROM deliveries
                WHERE delivered_at >= ? AND delivered_at <= ? AND target != 'clipboard'
                """, arguments: [windowStart, end])!
            return (row["attempts"], row["failures"], row["readable"], row["avg_ms"])
        }

        let avgCaptureMs = try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT CAST(AVG(capture_duration_ms) AS INTEGER) FROM captures
                WHERE created_at >= ? AND created_at <= ? AND capture_duration_ms IS NOT NULL
                """, arguments: [windowStart, end])
        }

        let inboxTotal = try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM captures WHERE deleted_at IS NULL") ?? 0 }
        let hops = try queue.read { try HopUsage.read($0, since: windowStart, until: end) }
        let inboxOpened = try countEvent(queue, EventStore.Name.inboxOpened, since: windowStart, until: end)
        let searches = try countEvent(queue, EventStore.Name.inboxSearch, since: windowStart, until: end)
        let viewed = try countEvent(queue, EventStore.Name.captureViewed, since: windowStart, until: end)
        let redeliver = try countEvent(queue, EventStore.Name.inboxRedeliver, since: windowStart, until: end)

        return DogfoodReport(
            hops: hops,
            days: days,
            windowStartMs: windowStart,
            capturedCount: byName[EventStore.Name.captureCompleted] ?? 0,
            duplicateCount: byName[EventStore.Name.captureDuplicate] ?? 0,
            rejectedCount: byName[EventStore.Name.captureRejected] ?? 0,
            perDay: perDayRows,
            panelP95ms: DogfoodReport.percentile95(panelMs),
            panelCount: panelMs.count,
            attempts: attempts,
            chosenTargetFailures: failures,
            readableFailures: readable,
            avgDeliveryMs: avgMs,
            avgCaptureMs: avgCaptureMs,
            inboxTotalCaptures: inboxTotal,
            inboxOpenedCount: inboxOpened,
            searchCount: searches,
            viewedCount: viewed,
            redeliverCount: redeliver)
    }

    static func percentile95(_ sortedInput: [Int]) -> Int? {
        guard !sortedInput.isEmpty else { return nil }
        let v = sortedInput.sorted()
        let idx = max(0, Int((Double(v.count) * 0.95).rounded(.up)) - 1)
        return v[idx]
    }

    private static func countEvent(_ queue: DatabaseQueue, _ name: String, since: Int64, until: Int64) throws -> Int {
        try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM events WHERE ts >= ? AND ts <= ? AND name = ?",
                                             arguments: [since, until, name]) ?? 0 }
    }

    /// The §3 gate table as plain text (CLI output). Thresholds mirror evolution-decisions §3
    /// plus the MVP panel budget.
    public func gateTable() -> String {
        var out: [String] = []
        out.append("Beamhop dogfood report — window: last \(days) day(s)")
        out.append("Ordinary Hop telemetry — persisted starts and transport receipts, not task completion")
        out.append("  Attempts \(hops.attempts): copied \(hops.copied), prepared \(hops.prepared), failed \(hops.failed), interrupted/unknown \(hops.interrupted), pending \(hops.pending)")
        out.append("  Pocket: \(hops.savedDrafts) distinct drafts saved, \(hops.reusedDrafts) distinct drafts reused, \(hops.pocketHandoffs) batch attempts, \(hops.recoveredBackups) backup recoveries")
        out.append("  Retained conclusions written in window: \(hops.retainedConclusions) for \(hops.returnedHandoffs) handoffs (not a completion rate)")
        out.append("  Retained backups without start telemetry (all dates): \(hops.untrackedBackups); malformed events in window: \(hops.ignoredEvents)")
        out.append("  Tracking begins with this build; old attempts are not backfilled. Local events retain 180 days; missing telemetry is not zero historical usage.")
        out.append("  Real participants, tasks, steps saved and repeat-use intent require the private field-trial record; fixtures are not real tasks.")
        out.append("Legacy delivery rows — may overlap Hop transport; do not add denominators or infer whole-product success")

        func mark(_ ok: Bool) -> String { ok ? "✓" : "✗" }
        func fmt(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }

        out.append("")
        out.append("Historical gates (legacy transport only, not release acceptance)     value      threshold")
        out.append("  \(mark(pressesPerDay >= 10)) ⌘⇧Space frequency               \(fmt(pressesPerDay))/day    ≥ 10/day")
        out.append("  \(mark((successRate ?? 0) >= 0.95)) legacy nonfailed target rows     \(successRate.map { fmt($0 * 100) + "%" } ?? "n/a")       ≥ 95%")
        out.append("  \(mark(inboxTotalCaptures >= 200)) Inbox accumulation              \(inboxTotalCaptures)         ≥ 200")
        out.append("  \(mark(inboxVisitsPerWeek >= 3)) Inbox revisits                 \(fmt(inboxVisitsPerWeek))/week  ≥ 3/week")
        let coverageOK = chosenTargetFailures == 0 || readableFailures == chosenTargetFailures
        out.append("  \(mark(coverageOK)) failures show readable reason       \(readableFailures)/\(chosenTargetFailures)    100%")
        if let p = panelP95ms {
            out.append("  \(mark(p <= 300)) panel P95 latency                 \(p) ms      ≤ 300ms (MVP)")
        } else {
            out.append("  – panel P95 latency                 no data     ≤ 300ms (MVP)")
        }

        out.append("")
        out.append("Presses in window: \(pressCount) (captured \(capturedCount), duplicate-swallowed \(duplicateCount), rejected \(rejectedCount))")
        if !perDay.isEmpty {
            out.append("Per day: " + perDay.map { "\($0.day)=\($0.presses)" }.joined(separator: "  "))
        }
        out.append("Component averages: capture \(avgCaptureMs.map { "\($0)ms" } ?? "n/a"); legacy delivery \(avgDeliveryMs.map { "\($0)ms" } ?? "n/a"). Different sample sets; do not sum into end-to-end latency.")
        out.append("Panel samples: \(panelCount)   Inbox: \(searchCount) searches, \(viewedCount) detail views, \(redeliverCount) re-deliveries")
        out.append("Legacy failed-row fraction (not verified fallback frequency): \(attempts > 0 ? fmt(Double(chosenTargetFailures) / Double(attempts) * 100) + "%" : "n/a") of chosen-target attempts")
        out.append("")
        out.append("All local. No data leaves this machine.")
        return out.joined(separator: "\n")
    }
}
