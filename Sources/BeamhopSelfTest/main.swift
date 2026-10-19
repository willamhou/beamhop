import Foundation
import BeamhopCore

// `--seed <db-path>`: insert one sample capture into the given DB and exit (dev helper for
// testing the MCP server end-to-end).
if let i = CommandLine.arguments.firstIndex(of: "--seed"), i + 1 < CommandLine.arguments.count {
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let store = CaptureStore(try Database(path: url))
    let c = Capture(source: .ax, appBundleID: "com.apple.Safari", appName: "Safari",
                    windowTitle: "Fix race condition in queue",
                    url: "https://github.com/foo/bar/pull/123",
                    selectedText: "if (q.size > 0) { ... }",
                    domainHint: .githubPR,
                    pid: 4242, captureMethod: "ax")
    try store.insert(c)
    print("seeded \(c.id) -> \(url.path) (\(try store.count()) total)")
    exit(0)
}

// `--dogfood <db> [--days N]`: print the dogfood gate report (evolution-decisions §3) from a
// real inbox.sqlite and exit. Thin wrapper: scripts/dogfood-metrics.sh calls this.
if let i = CommandLine.arguments.firstIndex(of: "--dogfood"), i + 1 < CommandLine.arguments.count {
    var days = 14
    if let d = CommandLine.arguments.firstIndex(of: "--days"), d + 1 < CommandLine.arguments.count,
       let n = Int(CommandLine.arguments[d + 1]), n > 0 {
        days = n
    }
    let db = try Database(path: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    print(try DogfoodReport.generate(db: db, days: days).gateTable())
    exit(0)
}

// Minimal XCTest-free test runner (CLT has no XCTest). Mirrors StorageTests.
// Exits non-zero on any failure.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") }
    else { print("  ✗ FAIL: \(msg)"); failures += 1 }
}

func freshDB() throws -> (Database, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("beamhop-selftest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("inbox.sqlite")
    return (try Database(path: url), url)
}

func freshStore() throws -> (CaptureStore, URL) {
    let (db, url) = try freshDB()
    return (CaptureStore(db), url)
}

func sample(id: String = ULID.captureID(), appName: String = "Safari",
            windowTitle: String? = "Fix race condition in queue",
            selectedText: String? = "if (q.size > 0) { ... }") -> Capture {
    Capture(id: id, source: .ax, appBundleID: "com.apple.Safari", appName: appName,
            windowTitle: windowTitle, url: "https://github.com/foo/bar",
            selectedText: selectedText, pid: 123, captureMethod: "ax")
}

do {
    print("== insert + recent ==")
    do {
        let (store, _) = try freshStore()
        try store.insert(sample())
        let r = try store.recent()
        check(r.count == 1, "recent returns 1")
        check(r.first?.appName == "Safari", "appName round-trips")
        check(try store.count() == 1, "count == 1")
    }

    print("== english word search (unicode61) ==")
    do {
        let (store, _) = try freshStore()
        try store.insert(sample(windowTitle: "Fix race condition", selectedText: "queue overflow bug"))
        check(try store.search("queue").count == 1, "match 'queue'")
        check(try store.search("race").count == 1, "match 'race'")
        check(try store.search("nonexistentword").count == 0, "no match for absent word")
    }

    print("== CJK substring search (trigram, >= 3 chars) ==")
    do {
        let (store, _) = try freshStore()
        try store.insert(sample(windowTitle: "修复队列竞态条件", selectedText: "中文搜索测试内容"))
        check(try store.search("搜索测试").count == 1, "match 中文 substring")
        check(try store.search("队列竞态").count == 1, "match title substring")
        check(try store.search("不存在的词").count == 0, "no match for absent CJK")
    }

    print("== soft delete excluded from recent + search (codex) ==")
    do {
        let (store, _) = try freshStore()
        let c = sample(selectedText: "uniquetoken123")
        try store.insert(c)
        check(try store.search("uniquetoken123").count == 1, "found before delete")
        try store.softDelete(id: c.id)
        check(try store.recent().count == 0, "recent excludes soft-deleted")
        check(try store.search("uniquetoken123").count == 0, "search excludes soft-deleted")
        check(try store.count() == 0, "count excludes soft-deleted")
    }

    print("== purge expired ==")
    do {
        let (store, _) = try freshStore()
        var old = sample()
        old.deletedAt = Int64(Date().addingTimeInterval(-40 * 86400).timeIntervalSince1970 * 1000)
        try store.insert(old)
        let recentDel = sample()
        try store.insert(recentDel)
        try store.softDelete(id: recentDel.id)
        let purged = try store.purgeExpired(retentionDays: 30)
        check(purged == 1, "purges only the 40-day-old soft-deleted row")
    }

    print("== purge cascades deliveries (FK v2, code review P2-1) ==")
    do {
        let (store, _) = try freshStore()
        var old = sample()
        old.deletedAt = Int64(Date().addingTimeInterval(-40 * 86400).timeIntervalSince1970 * 1000)
        try store.insert(old)
        try store.recordDelivery(Delivery(captureID: old.id, target: .claudeCode, status: .success))
        _ = try store.purgeExpired(retentionDays: 30)
        check(try store.deliveries(captureID: old.id).isEmpty,
              "physical purge removes cascaded delivery rows (no orphans)")
    }

    print("== provenance round-trip ==")
    do {
        let (store, _) = try freshStore()
        var c = sample()
        c.appVersion = "17.5"; c.captureDurationMs = 42; c.isPrivate = true
        c.truncated = true; c.domainHint = .githubPR
        try store.insert(c)
        let f = try store.fetch(id: c.id)
        check(f?.appVersion == "17.5", "app_version")
        check(f?.captureDurationMs == 42, "capture_duration_ms")
        check(f?.isPrivate == true, "is_private")
        check(f?.truncated == true, "truncated")
        check(f?.domainHint == .githubPR, "domain_hint")
        check(f?.osVersion == Version.os, "os_version")
    }

    print("== corruption recovery (spec §8.2) ==")
    do {
        let (store, url) = try freshStore()
        try store.insert(sample())
        // realistic corruption under WAL: garbage the main file AND drop -wal/-shm
        // (data lives in -wal, so corrupting only the main file is recoverable, not corruption)
        try Data("not a sqlite database".utf8).write(to: url)
        for s in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) }
        let db = try Database(path: url)
        check(db.recoveredFromCorruption, "recoveredFromCorruption == true")
        check(try CaptureStore(db).count() == 0, "rebuilt DB is empty")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        check(siblings.contains { $0.contains(".broken.") }, ".broken backup exists")
    }

    print("== ULID ==")
    do {
        let id = ULID.captureID()
        check(id.hasPrefix("cap_"), "cap_ prefix")
        check(id.count == 4 + 26, "full ULID length (26)")
        check(ULID.shortPrefix(of: id).count == 4 + 6, "short prefix length")
        // basic uniqueness sanity
        var seen = Set<String>()
        for _ in 0..<10_000 { seen.insert(ULID.captureID()) }
        check(seen.count == 10_000, "10k ULIDs unique")
    }
    print("== Week 3: DuplicateGate (<500ms same window) ==")
    do {
        var gate = DuplicateGate()
        let t0 = Date(timeIntervalSince1970: 1_000)
        check(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Doc", at: t0) == false, "first press never duplicate")
        check(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Doc", at: t0.addingTimeInterval(0.3)) == true, "<500ms same window → duplicate")
        check(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Other", at: t0.addingTimeInterval(0.4)) == false, "different title → not duplicate")
        check(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(0.45)) == false, "different bundle → not duplicate")
        check(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(0.9)) == true, "<500ms same window (new key) → duplicate")
        check(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(2.0)) == false, ">500ms → not duplicate")
        gate.reset()
        check(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(2.1)) == false, "reset clears memory")
        // nil title must equal nil title (window-less apps like menu-bar utilities)
        var g2 = DuplicateGate()
        check(g2.isDuplicate(bundleID: "app.a", title: nil, at: t0) == false, "nil-title first press ok")
        check(g2.isDuplicate(bundleID: "app.a", title: nil, at: t0.addingTimeInterval(0.1)) == true, "nil-title repeat → duplicate")
        check(g2.isDuplicate(bundleID: "app.a", title: "Now has title", at: t0.addingTimeInterval(0.2)) == false, "nil vs title → not duplicate")
    }

    print("== Week 3: PanelShortcut (⌘1-4 / ⌘0) ==")
    do {
        check(PanelShortcut.claudeCode.target == .claudeCode, "⌘1 → Claude Code")
        check(PanelShortcut.chatgptDesktop.target == .chatgptDesktop, "⌘2 → ChatGPT")
        check(PanelShortcut.cowork.target == .cowork, "⌘3 → Cowork")
        check(PanelShortcut.kimiWork.target == .kimiWork, "⌘4 → Kimi Work")
        check(PanelShortcut.inboxOnly.target == nil, "⌘0 → Inbox only (nil target)")
        check(PanelShortcut.allCases.count == 5, "exactly 5 shortcuts")
        check(Set(PanelShortcut.allCases.map(\.rawValue)) == Set(["0", "1", "2", "3", "4"]), "keys are 0-4, no drift")
        check(PanelShortcut.kimiWork.badge == "⌘4", "badge ⌘4")
        // 每个可投递 target 都有对应 shortcut（防新增 DeliveryTarget 后漏配键位）
        let mapped = Set(PanelShortcut.allCases.compactMap(\.target))
        for t in DeliveryTarget.allCases where t != .clipboard {
            check(mapped.contains(t), "target \(t.rawValue) has a panel shortcut")
        }
    }

    print("== Week 3: TargetMemory (记住上次投递目标) ==")
    do {
        var m = TargetMemory()
        check(m.last == .claudeCode, "default is Claude Code")
        m.markSucceeded(.kimiWork)
        check(m.last == .kimiWork, "success updates memory")
        m.markSucceeded(.chatgptDesktop)
        check(m.last == .chatgptDesktop, "later success overwrites")
        m.reset()
        check(m.last == nil, "reset clears")
        var m2 = TargetMemory(default: nil)
        check(m2.last == nil, "nil default supported")
        m2.markSucceeded(.cowork)
        check(m2.last == .cowork, "nil-default memory still records")
    }

    print("== Week 3: PromptRenderer (note + truncation) ==")
    do {
        let cap = Capture(source: .ax, appBundleID: "com.apple.Safari", appName: "Safari",
                          windowTitle: "PR #42", url: "https://github.com/a/b/pull/42",
                          selectedText: "hello world", pid: 1, captureMethod: "ax")
        let plain = PromptRenderer.fullMarkdown(cap, userNote: nil)
        check(plain.contains("Source: Safari · https://github.com/a/b/pull/42"), "source+url line")
        check(plain.contains("Title: PR #42"), "title line")
        check(plain.contains("<selected>\nhello world\n</selected>"), "selected block")
        check(!plain.contains("<body>"), "no empty body block")
        let noted = PromptRenderer.fullMarkdown(cap, userNote: "总结一下")
        check(noted.hasSuffix("\n总结一下\n"), "note appended at end")
        check(PromptRenderer.fullMarkdown(cap, userNote: "") == plain, "empty note ≡ nil note")
        // truncation: maxBody 10 cuts selected text and flags continuation
        let long = PromptRenderer.fullMarkdown(cap, userNote: nil, maxBody: 5)
        check(long.contains("hello\n…[truncated; full content in Beamhop Inbox]"), "truncation marker")
        check(!long.contains("hello world</selected>"), "truncated body not full")
        // claude trigger: fetch + save_result write-back convention (方案A 数据链路)
        let trig = PromptRenderer.claudeCodeTrigger(cap, userNote: nil)
        check(trig.hasPrefix("用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文"), "fetch prefix without note")
        check(trig.contains("save_result(origin_capture_id='\(cap.id)', content=你的结论, agent='claude_code')"),
              "write-back convention with origin + agent")
        let trigNote = PromptRenderer.claudeCodeTrigger(cap, userNote: "重点看竞态")
        check(trigNote.hasPrefix("用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文。重点看竞态"),
              "note sits between fetch and write-back")
        check(trigNote.contains("save_result"), "note variant still carries write-back")
        // generic agent variant
        let trigCodex = PromptRenderer.mcpTrigger(cap, userNote: nil, agent: "codex")
        check(trigCodex.contains("agent='codex'"), "generic trigger parameterizes agent")
    }

    print("== Week 3: CapturePanelModel (presentation) ==")
    do {
        let cap = Capture(source: .ax, appBundleID: "com.moonshot.kimichat", appName: "Kimi",
                          windowTitle: "Kimi Work", selectedText: String(repeating: "字", count: 25),
                          pid: 1, captureMethod: "ax")
        var confirmed: (DeliveryTarget?, String)?
        var cancelled = false
        let m = CapturePanelModel(capture: cap, initialTarget: .kimiWork,
                                  onConfirm: { t, n in confirmed = (t, n) },
                                  onCancel: { cancelled = true })
        check(m.summaryLine == "Kimi · Kimi Work · 20 chars", "summaryLine rounds chars down to 10s")
        check(m.previewText == String(repeating: "字", count: 25), "preview passes short text through")
        check(m.confirmLabel == "Deliver (Kimi Work)", "confirm label shows selected target")
        m.note = "总结一下这段"
        m.confirm()
        check(confirmed?.0 == .kimiWork && confirmed?.1 == "总结一下这段", "confirm carries target + note")
        check(!cancelled, "confirm does not cancel")
        // ⌘0: nil target confirm
        let m0 = CapturePanelModel(capture: cap, initialTarget: nil,
                                   onConfirm: { t, n in confirmed = (t, n) },
                                   onCancel: { cancelled = true })
        check(m0.confirmLabel == "Save to Inbox only", "nil target → Save to Inbox only")
        m0.confirm()
        check(confirmed?.0 == nil, "⌘0 confirm delivers nil target (Inbox only)")
        m0.cancel()
        check(cancelled, "cancel fires")
        // 无内容 → 无预览
        let empty = Capture(source: .ax, appBundleID: "a", appName: "A", pid: 1, captureMethod: "ax")
        let mE = CapturePanelModel(capture: empty, initialTarget: .cowork,
                                   onConfirm: { _, _ in }, onCancel: {})
        check(mE.previewText == nil, "no body → no preview")
        check(mE.summaryLine == "A", "summaryLine without title/chars")
        check(mE.targetLabel(.cowork) == "Cowork → clipboard", "cowork label honest about clipboard")
        check(mE.targetLabel(.clipboard) == "Clipboard", "clipboard label")
    }

    print("== Phase 1.5: EventStore + DogfoodReport (dogfood gate) ==")
    do {
        let (db, _) = try freshDB()
        let store = CaptureStore(db)
        let events = EventStore(db)

        // events round-trip + id prefix
        events.record(name: EventStore.Name.captureCompleted, detail: "method=ax ms=42",
                      captureID: "cap_x", date: Date())
        events.record(name: EventStore.Name.captureDuplicate, date: Date())
        events.record(name: EventStore.Name.inboxOpened, date: Date())
        check(try events.count() == 3, "3 events recorded")
        let firstID = try db.queue.read { try String.fetchOne($0, sql: "SELECT id FROM events LIMIT 1") }
        check(firstID?.hasPrefix("evt_") == true, "event ids use evt_ prefix")

        // prune: everything older than "now" goes away, fresh rows stay
        events.record(name: EventStore.Name.inboxOpened, date: Date().addingTimeInterval(-400 * 86400))
        let pruned = try events.prune(retentionDays: 180)
        check(pruned == 1, "prune removes only >retention events")
        check(try events.count() == 3, "recent events survive prune")

        // dogfood report math on seeded data
        let cap = sample()
        try store.insert(cap)
        for i in 1...20 {
            events.record(name: EventStore.Name.panelShown, detail: "ms=\(i)", captureID: cap.id, date: Date())
        }
        // deliveries: 4 chosen-target attempts (2 ok, 2 failed — one without a reason),
        // plus a clipboard fallback row that must NOT count as an attempt.
        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .success, durationMs: 300))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .success, durationMs: 500))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .failed, errorMessage: "no terminal", durationMs: 900))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .chatgptDesktop, status: .failed, durationMs: 700))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .clipboard, status: .success))
        events.record(name: EventStore.Name.inboxOpened, date: Date().addingTimeInterval(-86400))

        let r = try DogfoodReport.generate(db: db, days: 14)
        check(r.pressCount == 2, "press count = captured(1) + duplicate(1)")
        check(r.panelP95ms == 19, "panel P95 of 1...20 == 19")
        check(r.attempts == 4, "clipboard rows excluded from chosen-target attempts")
        check(r.chosenTargetFailures == 2, "2 failed attempts")
        check(r.readableFailures == 1, "1 of 2 failures carries a reason")
        if let sr = r.successRate { check(abs(sr - 0.5) < 0.0001, "success rate 50%") } else { check(false, "success rate defined") }
        check(r.avgDeliveryMs == 600, "avg delivery ms over duration rows == 600")
        check(r.inboxOpenedCount == 2, "2 inbox opens in window")
        check(abs(r.inboxVisitsPerWeek - 1.0) < 0.0001, "2 opens / 14 days == 1/week")
        check(r.inboxTotalCaptures == 1, "inbox total is cumulative")
        let table = r.gateTable()
        check(table.contains("≥ 10/day"), "gate table lists press threshold")
        check(table.contains("≥ 95%"), "gate table lists delivery threshold")
    }

    print("== Phase 1.5: migration v5 reconcile (simulated plan-A-branch DB) ==")
    do {
        // Simulate the collaborator machine's real inbox.sqlite: built from the
        // feat/mcp-writeback-dedup branch, where "v3" meant the results table — grdb_migrations
        // has v1/v2/v3 recorded, `results` exists, but `events` and deliveries.duration_ms
        // were never created.
        let (db, url) = try freshDB()
        try db.queue.write { d in
            try d.execute(sql: "DELETE FROM grdb_migrations WHERE identifier IN ('v4', 'v5')")
            try d.execute(sql: "DROP TABLE events")
            // best effort: old SQLite can't drop columns — v5's addColumnIfMissing then no-ops
            try? d.execute(sql: "ALTER TABLE deliveries DROP COLUMN duration_ms")
        }

        // Reopen with the merged migrator: v3 skipped BY NAME, v4 no-ops (IF NOT EXISTS),
        // v5 recreates the dogfood schema. Must not throw.
        let db2 = try Database(path: url)
        check(true, "plan-A-branch DB reopens without migration error")
        let events2 = EventStore(db2)
        events2.record(name: EventStore.Name.captureCompleted, date: Date())
        check(try events2.count() == 1, "events table recreated by v5 and writable")
        let store2 = CaptureStore(db2)
        let cap2 = sample()
        try store2.insert(cap2)
        try store2.recordDelivery(Delivery(captureID: cap2.id, target: .claudeCode, status: .success, durationMs: 55))
        check(try store2.deliveries(captureID: cap2.id).first?.durationMs == 55,
              "deliveries.duration_ms present after reconcile")
        _ = try DogfoodReport.generate(db: db2, days: 7)   // must not throw on reconciled schema
        check(true, "dogfood report runs on reconciled DB")
    }

    print("== Phase 1.5: zh-Hans UI strings (language toggle) ==")
    do {
        let path = FileManager.default.currentDirectoryPath
            + "/packaging/lproj/zh-Hans.lproj/Localizable.strings"
        check(FileManager.default.fileExists(atPath: path), "zh-Hans strings file exists in repo")
        let dict = NSDictionary(contentsOfFile: path) as? [String: String]
        check(dict != nil, "strings file parses as a plist dictionary")
        if let dict {
            check(dict.count >= 115, "≥115 zh translations (\(dict.count))")
            check(dict.values.allSatisfy { !$0.isEmpty }, "no empty translations")
            check(dict["Language"] == "语言", "language-menu keys present")
            check(dict["Deliver (%@)"] != nil, "format-style key present for L10n.f")
            // duplicate keys would be silently merged by NSDictionary — compare raw assignment
            // lines against the parsed count to catch them
            let raw = try String(contentsOfFile: path, encoding: .utf8)
            let assignmentLines = raw.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("\"") && $0.contains(" = ") }
                .count
            check(assignmentLines == dict.count, "no duplicate keys (\(assignmentLines) lines = \(dict.count) parsed)")
        }
    }

    print("== Phase 1.5: AXDeadline (total AX budget) ==")
    do {
        let d = AXDeadline(budget: 1.0)
        check(!d.expired, "fresh deadline not expired")
        check(d.remaining <= 1.0 && d.remaining > 0.9, "remaining ≈ budget when fresh")
        check(d.callTimeout(default: 0.8) <= 0.8, "call timeout capped by per-call default")
        Thread.sleep(forTimeInterval: 0.05)
        check(d.callTimeout(default: 0.8) <= 0.95, "call timeout capped by remaining budget")
        let zero = AXDeadline(budget: 0)
        check(zero.expired, "zero budget is immediately expired")
        check(zero.remaining == 0, "remaining clamps at zero")
        check(zero.callTimeout(default: 0.8) == 0.05, "expired deadline still yields a floor timeout (0.05s)")
        let neg = AXDeadline(budget: -5)
        check(neg.expired && neg.remaining == 0, "negative budget treated as expired")
    }

    print("== Week 3: DeliveryTarget raw values ==")
    do {
        check(DeliveryTarget.kimiWork.rawValue == "kimi_work", "kimi_work raw value")
        check(DeliveryTarget(rawValue: "kimi_work") == .kimiWork, "kimi_work decodes")
        check(DeliveryTarget.allCases.count == 5, "5 delivery targets")
        let encoder = JSONEncoder()
        for t in DeliveryTarget.allCases {
            let data = try encoder.encode(t)
            check(String(data: data, encoding: .utf8) == "\"\(t.rawValue)\"", "\(t.rawValue) JSON round-trip shape")
        }
    }

    print("== MCP dedup: contentIdentity ==")
    do {
        let a = sample()
        let b = sample()   // identical content, different id/time
        check(a.contentIdentity == b.contentIdentity, "identical re-capture → same identity")
        var c = sample(); c.selectedText = "different text"
        check(a.contentIdentity != c.contentIdentity, "different text → different identity")
        var d = sample(); d.appBundleID = "com.google.Chrome"
        check(a.contentIdentity != d.contentIdentity, "different app → different identity")
        var e = sample(); e.url = nil
        check(a.contentIdentity != e.contentIdentity, "missing url → different identity")
    }

    print("== MCP dedup: searchDeduplicated collapses re-captures ==")
    do {
        let (store, url) = try freshStore()
        let base = Int64(Date().timeIntervalSince1970 * 1000)
        // 3 byte-identical re-captures of the same GitHub page (minutes apart — beyond the
        // <500ms DuplicateGate) + 1 distinct capture that also matches the query.
        for i in 0..<3 {
            var c = sample(id: "cap_dup\(i)", appName: "Google Chrome",
                           windowTitle: "AuSmith-hub/beamhop",
                           selectedText: "cross-app context hub for agents")
            c.appBundleID = "com.google.Chrome"
            c.url = "https://github.com/AuSmith-hub/beamhop"
            c.createdAt = base + Int64(i) * 60_000
            try store.insert(c)
        }
        var other = sample(selectedText: "cross-app delivery notes")
        other.createdAt = base + 4 * 60_000
        try store.insert(other)

        let reader = try CaptureReader.open(path: url)
        check(try reader.search("cross-app", limit: 20).count == 4, "raw search returns all 4 hits")
        let hits = try reader.searchDeduplicated("cross-app", limit: 10)
        check(hits.count == 2, "deduped search returns 2 groups")
        let dupGroup = hits.first { $0.duplicateCount == 3 }
        check(dupGroup != nil, "group of 3 re-captures reported")
        check(dupGroup?.capture.id == "cap_dup2", "representative is the newest of its group")
        check(dupGroup?.firstSeenAt == base, "first_seen_at = oldest capture")
        check(dupGroup?.lastSeenAt == base + 2 * 60_000, "last_seen_at = newest capture")
        let solo = hits.first { $0.duplicateCount == 1 }
        check(solo?.capture.id == other.id, "distinct capture is its own group")
        // soft-deleted twins must not inflate the count
        try store.softDelete(id: "cap_dup0")
        let hits2 = try CaptureReader.open(path: url).searchDeduplicated("cross-app", limit: 10)
        check(hits2.first { $0.capture.id == "cap_dup2" }?.duplicateCount == 2,
              "soft-deleted twin excluded from duplicate_count")
    }

    print("== 方案A: result write-back round-trip ==")
    do {
        let (store, _) = try freshStore()
        let c = sample()
        try store.insert(c)
        try store.insertResult(CaptureResult(originCaptureID: c.id, agent: "codex",
                                             sessionID: "sess-1", content: "结论:竞态根因是锁顺序"))
        let rs = try store.results(captureID: c.id)
        check(rs.count == 1, "one result for origin")
        check(rs.first?.agent == "codex", "agent round-trips")
        check(rs.first?.sessionID == "sess-1", "session_id round-trips")
        check(rs.first?.content == "结论:竞态根因是锁顺序", "content round-trips (CJK verbatim)")
        check(rs.first?.id.hasPrefix("res_") == true, "res_ id prefix")
        check(try store.recentResults().count == 1, "recentResults sees it")
        // 多 agent 共享：同一 origin 可以有多个写回（显式错开 1ms，避免同毫秒并列）
        try store.insertResult(CaptureResult(originCaptureID: c.id, agent: "claude_code",
                                             content: "补充:最小复现是两条并发 enqueue",
                                             createdAt: Int64(Date().timeIntervalSince1970 * 1000) + 1))
        check(try store.results(captureID: c.id).count == 2, "two agents can write back to one origin")
        check(try store.recentResults(limit: 1).first?.agent == "claude_code", "newest first")
    }

    print("== 方案A: result FK rejects unknown origin + cascades on purge ==")
    do {
        let (store, _) = try freshStore()
        var rejected = false
        do {
            try store.insertResult(CaptureResult(originCaptureID: "cap_doesnotexist",
                                                 agent: "codex", content: "orphan"))
        } catch { rejected = true }
        check(rejected, "unknown origin rejected (FK)")
        var old = sample()
        old.deletedAt = Int64(Date().addingTimeInterval(-40 * 86400).timeIntervalSince1970 * 1000)
        try store.insert(old)
        try store.insertResult(CaptureResult(originCaptureID: old.id, agent: "codex", content: "stale"))
        _ = try store.purgeExpired(retentionDays: 30)
        check(try store.results(captureID: old.id).isEmpty, "physical purge cascades results (no orphans)")
    }

    print("== 方案A: ResultStore.open guards (MCP 进程视角) ==")
    do {
        let (_, url) = try freshStore()
        check((try? ResultStore.open(path: url)) != nil, "opens on v3-migrated DB")
        // 模拟 v3 之前的旧库:drop results 表
        let db2 = try Database(path: url)
        try db2.queue.write { try $0.execute(sql: "DROP TABLE results") }
        do {
            _ = try ResultStore.open(path: url)
            check(false, "should throw schemaOutdated")
        } catch DatabaseError.schemaOutdated {
            check(true, "schemaOutdated when results table missing")
        }
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beamhop-nope-\(UUID().uuidString).sqlite")
        do {
            _ = try ResultStore.open(path: missing)
            check(false, "should throw fileNotFound")
        } catch DatabaseError.fileNotFound {
            check(true, "fileNotFound when DB absent")
        }
    }
    print("== Focus recovery + self-capture regression ==")
    do {
        check(CaptureFocusPolicy.isSelf(sourcePID: 42, sourceBundleID: "unknown", ownPID: 42),
              "SwiftPM self PID rejected even without bundle ID")
        check(CaptureFocusPolicy.isSelf(sourcePID: 43, sourceBundleID: "com.beamhop.app", ownPID: 42),
              "another Beamhop instance rejected by bundle ID")
        check(!CaptureFocusPolicy.isSelf(sourcePID: 7, sourceBundleID: "com.apple.Safari", ownPID: 42),
              "external source allowed")
        func restore(_ front: Int32?, source: Int32 = 7, terminated: Bool = false,
                     window: Bool = false) -> Bool {
            CaptureFocusPolicy.shouldRestore(sourcePID: source, ownPID: 42, frontmostPID: front,
                                             sourceTerminated: terminated, hasVisibleBeamhopWindow: window)
        }
        check(restore(42), "cancel/save/clipboard restores source while Beamhop owns focus")
        check(!restore(9), "delivery target or user's clicked app keeps focus")
        check(!restore(7), "already active source needs no activation")
        check(!restore(nil), "unknown foreground is left alone")
        check(!restore(42, terminated: true), "exited source never activated")
        check(!restore(42, window: true), "Inbox/new panel keeps focus")
        check(!restore(42, source: 42), "never restores Beamhop itself")
    }

    print("== Inbox external write-back + selection regression ==")
    do {
        let (db, path) = try freshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = CaptureStore(db)
        let events = EventStore(db)
        var rows: [Capture] = []
        for index in 0..<61 {
            var row = sample(windowTitle: "Document \(index)")
            row.createdAt = Int64(index + 1000)
            try store.insert(row)
            rows.append(row)
        }
        let origin = rows[0], other = rows[1]
        let model = InboxModel()
        model.configure(store: store, events: events, onDeliver: { _, _ in })
        model.reload()
        model.selectedID = origin.id
        check(model.selectedResults.isEmpty, "empty conclusion state")
        let before = try events.count()
        let writer = try ResultStore.open(path: path)
        let result = CaptureResult(originCaptureID: origin.id, agent: "codex", sessionID: "test-session",
                                   content: "结论\n" + String(repeating: "证据", count: 1500), createdAt: 3000)
        try writer.insert(result)
        try writer.insert(CaptureResult(originCaptureID: other.id, agent: "kimi", content: "other"))
        try store.recordDelivery(Delivery(captureID: origin.id, target: .claudeCode,
                                          deliveredAt: 2000, status: .success))
        model.refreshSelectedDetails()
        check(model.selectedResults == [result], "row 61 sees external write-back verbatim, including session and long content")
        check(model.resultCounts[origin.id] == 1, "selected result badge refreshed")
        check(model.deliveries[origin.id]?.count == 1, "row 61 delivery history loaded")
        check(try events.count() == before, "polling does not inflate engagement events")
        model.selectedID = other.id
        check(model.selectedResults.first?.content == "other", "selection never leaks previous capture's conclusion")
        model.selectedID = nil
        check(model.selectedResults.isEmpty, "deselection clears conclusion")
        model.selectedID = origin.id
        model.softDelete(origin)
        check(model.selectedID == nil && model.selectedResults.isEmpty, "soft delete clears selected detail")
        model.selectedID = other.id
        try db.queue.write { try $0.execute(sql: "DROP TABLE results") }
        model.refreshSelectedDetails()
        check(model.detailErrorMessage != nil, "conclusion read error is visible")
        check(model.selectedResults.isEmpty, "conclusion read error does not leave stale content")
    }

    print("== Inbox result pagination + timeline regression ==")
    do {
        let (store, path) = try freshStore()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let origin = sample()
        try store.insert(origin)
        for index in 0..<101 {
            try store.insertResult(CaptureResult(originCaptureID: origin.id, agent: "codex",
                                                 content: "\(index)", createdAt: Int64(index)))
        }
        let model = InboxModel()
        model.configure(store: store, events: nil, onDeliver: { _, _ in })
        model.reload()
        model.selectedID = origin.id
        check(model.resultCounts[origin.id] == 101, "badge counts all conclusions")
        check(model.selectedResults.count == 100 && model.hasMoreResults, "latest 100 with explicit load-more")
        model.loadMoreResults()
        check(model.selectedResults.count == 101 && !model.hasMoreResults, "older conclusions remain accessible")
        model.reload()
        check(model.selectedID == origin.id && model.selectedResults.count == 101, "refresh preserves selection and pagination")

        let d = Delivery(id: 1, captureID: origin.id, target: .claudeCode, deliveredAt: 200, status: .success)
        let a = CaptureResult(id: "res_a", originCaptureID: origin.id, agent: "codex", content: "a", createdAt: 100)
        let b = CaptureResult(id: "res_b", originCaptureID: origin.id, agent: "codex", content: "b", createdAt: 200)
        let c = CaptureResult(id: "res_c", originCaptureID: origin.id, agent: "kimi", content: "c", createdAt: 200)
        check(TimelineBuilder.entries(deliveries: [d], results: [c, a, b])
                == [.result(a), .delivery(d), .result(b), .result(c)], "chronological timeline with deterministic delivery-first ties")
        check(TimelineBuilder.entries(deliveries: [], results: []).isEmpty, "empty timeline")
    }
} catch {
    print("EXCEPTION: \(error)")
    failures += 1
}

print(failures == 0 ? "\nALL PASS ✅" : "\n\(failures) FAILURE(S) ❌")
exit(failures == 0 ? 0 : 1)
