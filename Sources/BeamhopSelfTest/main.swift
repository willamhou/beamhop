import Foundation
import BeamhopCore
import GRDB

typealias Database = BeamhopCore.Database
typealias DatabaseError = BeamhopCore.DatabaseError

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

// Explicit disposable protocol fixture; no registration or default-path access.
if let i = CommandLine.arguments.firstIndex(of: "--seed-hop"), i + 1 < CommandLine.arguments.count {
    let db = try Database(path: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    let source = Capture(source: .ax, appBundleID: "fixture.source", appName: "Browser",
                         selectedText: "never-export-original", extractedBody: "unselected body", pid: 1, captureMethod: "fixture")
    try CaptureStore(db).insert(source)
    var material = HopMaterial(capture: source); material.text = "edited snapshot"
    let library = try HopLibrary(db)
    let enabled = try library.begin(HopDraft(materials: [material,
        HopMaterial(name: "fixture.png", path: "/private/fixture/hidden.png", image: true, bytes: 1)],
        instruction: "/review\nkeep literal", route: .init(target: .clipboard), requestsResultReturn: true))
    let disabled = try library.begin(HopDraft(materials: [HopMaterial(text: "disabled")], route: .init(target: .clipboard)))
    try library.finish(enabled.id, status: .copied)
    try library.finish(disabled.id, status: .copied)
    let ids = ["enabled": enabled.id, "disabled": disabled.id, "capture": source.id]
    print(String(decoding: try JSONSerialization.data(withJSONObject: ids), as: UTF8.self))
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

    print("== Week 3: PanelShortcut (⌘1-4 / ⌘0 / ⌘5 先留着) ==")
    do {
        check(PanelShortcut.claudeCode.target == .claudeCode, "⌘1 → Claude Code")
        check(PanelShortcut.chatgptDesktop.target == .chatgptDesktop, "⌘2 → ChatGPT")
        check(PanelShortcut.clipboard.target == .clipboard, "⌘3 → 剪贴板 (honest, not fake Cowork)")
        check(PanelShortcut.kimiWork.target == .kimiWork, "⌘4 → Kimi Work")
        check(PanelShortcut.inboxOnly.target == nil, "⌘0 → Inbox only (nil target)")
        check(PanelShortcut.hold.isHold && PanelShortcut.hold.target == nil, "⌘5 → 先留着 (hold, nil target)")
        check(PanelShortcut.allCases.count == 6, "exactly 6 shortcuts")
        check(Set(PanelShortcut.allCases.map(\.rawValue)) == Set(["0", "1", "2", "3", "4", "5"]),
              "keys are 0-5, no drift")
        check(PanelShortcut.kimiWork.badge == "⌘4", "badge ⌘4")
        check(PanelShortcut.hold.badge == "⌘5", "badge ⌘5")
        // 每个可投递 target 都有对应 shortcut（防新增 DeliveryTarget 后漏配键位）；
        // .cowork 除外——S2 集成未完成，面板不假装它能投递。
        let mapped = Set(PanelShortcut.allCases.compactMap(\.target))
        for t in DeliveryTarget.allCases where t != .cowork {
            check(mapped.contains(t), "target \(t.rawValue) has a panel shortcut")
        }
    }

    print("== 可用去处: TargetAvailability (没有装的不显示, 不做假选择) ==")
    do {
        let all = TargetAvailability.resolve(hasClaudeCLI: true, hasChatGPTApp: true, hasKimiApp: true)
        check(all == [.claudeCode, .chatgptDesktop, .kimiWork, .clipboard], "full house: apps then clipboard")
        check(all.last == .clipboard, "clipboard always available (honest fallback)")
        let none = TargetAvailability.resolve(hasClaudeCLI: false, hasChatGPTApp: false, hasKimiApp: false)
        check(none == [.clipboard], "bare machine: clipboard only")
        let partial = TargetAvailability.resolve(hasClaudeCLI: false, hasChatGPTApp: true, hasKimiApp: false)
        check(partial == [.chatgptDesktop, .clipboard], "partial: only what's installed")
        // usable(): 记住的目标消失时回退, Inbox(nil) 保持 Inbox
        check(TargetAvailability.usable(.kimiWork, among: all) == .kimiWork, "available target kept")
        check(TargetAvailability.usable(.kimiWork, among: partial) == nil, "vanished target requires a new choice")
        check(TargetAvailability.usable(nil, among: all) == nil, "Inbox choice stays Inbox")
        // 面板模型用 visibleTargets 过滤: cowork 不在列表时不会成为 selected
        let mVis = CapturePanelModel(capture: sample(), initialTarget: .cowork,
                                     visibleTargets: [.claudeCode, .clipboard],
                                     onConfirm: { _, _ in }, onCancel: {})
        check(mVis.selectedTarget == nil && !mVis.canConfirm, "invisible initial target blocks handoff")
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
        check(m.confirmLabel == "Continue in Kimi Work", "confirm label shows selected target")
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

    print("== 详情链: TimelineBuilder merge (2026-10-19 spec) ==")
    do {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let d1 = Delivery(captureID: "cap_t", target: .claudeCode, deliveredAt: now, status: .success)
        let d2 = Delivery(captureID: "cap_t", target: .clipboard, deliveredAt: now + 2000,
                          status: .failed, errorMessage: "composer not found")
        let r1 = CaptureResult(originCaptureID: "cap_t", agent: "claude_code",
                               content: "结论:锁顺序", createdAt: now + 1000)
        let r2 = CaptureResult(id: "res_x", originCaptureID: "cap_t", agent: "kimi",
                               content: "补充:最小复现", createdAt: now + 2000)
        // 故意乱序输入
        let e = TimelineBuilder.entries(deliveries: [d2, d1], results: [r2, r1])
        check(e.count == 4, "merge keeps every event")
        check(e.map(\.timestamp) == [now, now + 1000, now + 2000, now + 2000],
              "ascending by timestamp")
        check(e[0] == .delivery(d1) && e[1] == .result(r1), "delivery then its result")
        if case .delivery = e[2] { check(true, "same-ms tie: delivery before result") }
        else { check(false, "same-ms tie: delivery before result") }
        check(e[3] == .result(r2), "tie keeps the result after")
        check(e[0].stableID != e[1].stableID, "stableIDs unique across kinds")
        check(TimelineBuilder.entries(deliveries: [], results: []).isEmpty, "empty in, empty out")
    }

    print("== 先留着: PocketStore hold stack (essay 01) ==")
    do {
        let (db, _) = try freshDB()
        let captures = CaptureStore(db)
        let pocket = PocketStore(db)
        let c1 = sample(selectedText: "第一段材料")
        let c2 = sample(selectedText: "第二段材料")
        let c3 = sample(selectedText: "第三段材料")
        try captures.insert(c1); try captures.insert(c2); try captures.insert(c3)

        let i1 = try pocket.hold(captureID: c1.id, note: "交代一", intendedTarget: .claudeCode)
        let i2 = try pocket.hold(captureID: c2.id, note: nil, intendedTarget: nil)
        let i3 = try pocket.hold(captureID: c3.id, note: "", intendedTarget: .kimiWork)
        check(try pocket.count() == 3, "holds 3 items")
        check(i1.position == 1 && i2.position == 2 && i3.position == 3, "positions append in order")
        check(i2.intendedTarget == nil, "undecided target round-trips nil")
        check(i3.note == nil, "empty note normalizes to nil")

        let stack = try pocket.liveStack()
        check(stack.map { $0.1.id } == [c1.id, c2.id, c3.id], "stack preserves hold order")
        check(stack[0].1.selectedText == "第一段材料", "joins the capture back")

        try pocket.remove(id: i1.id)
        let after = try pocket.stack()
        check(after.count == 2 && after[0].position == 1 && after[1].position == 2,
              "remove re-normalizes positions densely")

        // soft-deleted capture leaves the live view but the row stays until purge cascade
        try captures.softDelete(id: c2.id)
        check(try pocket.liveStack().count == 1, "liveStack excludes soft-deleted captures")
        check(try pocket.count() == 2, "physical row remains until purge")
    }

    print("== 两层去处: WorkStore named destinations (essay 02) ==")
    do {
        let (db, _) = try freshDB()
        let works = WorkStore(db)

        let w = try works.register(name: "让发送不打断阅读", boundTo: .claudeCode)
        check(!w.needsConfirmation, "registration IS the first confirmation")
        check(w.confirmedTarget == .claudeCode, "confirmedTarget set at registration")

        // 同名再取（大小写不敏感）
        check(try works.fetch(name: "让发送不打断阅读")?.id == w.id, "fetch by exact name")
        check(try works.fetch(name: " 让发送不打断阅读 ")?.id == w.id, "fetch trims whitespace")
        check(try works.fetch(name: "LET发送不打断阅读") == nil, "NOCASE unique ≠ fuzzy match")

        // 换绑：confirmed 不动，needsConfirmation 亮起
        let rebound = try works.rebind(id: w.id, to: .kimiWork)
        check(rebound?.boundTarget == .kimiWork, "rebind moves boundTarget")
        check(rebound?.needsConfirmation == true, "rebind requires confirmation")
        check(rebound?.confirmedTarget == .claudeCode, "confirmedTarget untouched by rebind")

        // 重复 rebind 到同一 target：幂等
        let again = try works.rebind(id: w.id, to: .kimiWork)
        check(again?.needsConfirmation == true, "idempotent rebind keeps the flag")

        try works.confirm(id: w.id)
        let confirmed = try works.fetch(id: w.id)
        check(confirmed?.confirmedTarget == .kimiWork, "confirm adopts boundTarget")
        check(confirmed?.needsConfirmation == false, "confirmed clears the flag")
    }

    print("== 两层去处: CapturePanelModel 两步确认 + 先留着回调 ==")
    do {
        let cap = sample()
        let work = Work(name: "焦点行为检查", boundTarget: .kimiWork, confirmedTarget: .claudeCode)

        // Changed receiver: first confirm acknowledges the app only.
        var fired: [(DeliveryTarget?, String)] = []
        let m1 = CapturePanelModel(
            capture: cap, initialTarget: work.boundTarget, boundWork: work,
            onConfirm: { t, n in fired.append((t, n)) }, onCancel: {})
        check(m1.workNeedsConfirmation, "panel sees the unconfirmed rebind")
        check(m1.confirmLabel.contains("Use "), "label says ack-first, honestly")
        m1.confirm()
        check(fired.isEmpty, "first confirm does NOT deliver")
        check(m1.rebindAcknowledged, "first confirm arms the ack")
        m1.confirm()
        check(fired.count == 1 && fired[0].0 == .kimiWork, "second confirm delivers to the NEW address")

        // 已确认 → 单步直送
        let confirmedWork = Work(name: "焦点行为检查", boundTarget: .kimiWork, confirmedTarget: .kimiWork)
        let m2 = CapturePanelModel(
            capture: cap, initialTarget: .kimiWork, boundWork: confirmedWork,
            onConfirm: { t, _ in fired.append((t, "x")) }, onCancel: {})
        check(!m2.workNeedsConfirmation, "confirmed work: no gate")
        m2.confirm()
        check(fired.last?.0 == .kimiWork, "single-step deliver when confirmed")

        // 两层显示
        check(m2.destinationTitle == "焦点行为检查", "title = work name")
        check(m2.destinationSubtitle == m2.targetLabel(.kimiWork), "subtitle = receiver session")

        // 先留着回调
        var held: (DeliveryTarget?, String)?
        let m3 = CapturePanelModel(
            capture: cap, initialTarget: .chatgptDesktop,
            onConfirm: { _, _ in }, onCancel: {},
            onHold: { t, n in held = (t, n) })
        check(m3.canHold, "hold wired")
        m3.note = "回头一起看"
        m3.hold()
        check(held?.0 == .chatgptDesktop && held?.1 == "回头一起看", "hold passes target + note")

        // mismatch 闸：已确认的工作在面板里另选接收方 = 换绑，同样要两步确认
        var fired2: [(DeliveryTarget?, String)] = []
        let m4 = CapturePanelModel(
            capture: cap, initialTarget: .chatgptDesktop, boundWork: confirmedWork,
            onConfirm: { t, n in fired2.append((t, n)) }, onCancel: {})
        check(!m4.workNeedsConfirmation, "confirmed work stored state: no pending rebind")
        check(m4.receiverChanged, "picking a different receiver for a bound work IS a rebind")
        check(m4.confirmLabel.contains("Use "), "ack-first label on in-panel receiver switch")
        check(m4.destinationSubtitle?.contains("Receiving app changed") == true, "subtitle flags the switch")
        m4.confirm()
        check(fired2.isEmpty, "first confirm only acknowledges the new address")
        check(!m4.receiverChanged || m4.rebindAcknowledged, "ack disarms the gate")
        m4.confirm()
        check(fired2.count == 1 && fired2[0].0 == .chatgptDesktop, "second confirm delivers to the newly picked receiver")

        // 选中与绑定一致的接收方 → 闸不起
        let m5 = CapturePanelModel(
            capture: cap, initialTarget: .kimiWork, boundWork: confirmedWork,
            onConfirm: { t, n in fired2.append((t, n)) }, onCancel: {})
        check(!m5.receiverChanged, "unchanged receiver: no gate")
        check(m5.destinationSubtitle == m5.targetLabel(.kimiWork), "plain subtitle when receiver unchanged")
    }

    print("== Compact handoff regressions ==")
    do {
        var memory = TargetMemory()
        memory.markSucceeded(.claudeCode, workName: " A ")
        check(memory.lastWorkName == "A", "trim remembered work")
        memory.markSucceeded(.kimiWork)
        check(memory.lastWorkName == nil, "plain tool clears old work")
        let work = Work(name: "A", boundTarget: .claudeCode, confirmedTarget: .claudeCode)
        var sends = 0
        let model = CapturePanelModel(capture: sample(), initialTarget: .chatgptDesktop, boundWork: work,
                                      onConfirm: { _, _ in sends += 1 }, onCancel: {})
        model.confirm()
        model.selectedTarget = .kimiWork
        check(!model.rebindAcknowledged, "changing receiver invalidates ack")
        model.confirm()
        check(sends == 0, "new receiver cannot reuse old acknowledgment")
        model.confirm()
        check(sends == 1, "new receiver gets explicit confirmation")
        model.selectedTarget = nil
        model.confirm()
        check(sends == 2, "Inbox-only never requires receiver confirmation")
        model.chooseTool(.clipboard)
        check(model.boundWork == nil, "choosing a tool leaves named work")
        let missing = CapturePanelModel(capture: sample(), initialTarget: .claudeCode,
                                       visibleTargets: [.clipboard], boundWork: work,
                                       onConfirm: { _, _ in }, onCancel: {})
        check(missing.selectedTarget == nil, "missing named receiver never routes elsewhere")

        let (db, _) = try freshDB()
        let captures = CaptureStore(db)
        let pocket = PocketStore(db)
        let a = sample(), b = sample(), c = sample()
        for cap in [a, b, c] { try captures.insert(cap) }
        let one = try pocket.hold(captureID: a.id, note: "one", intendedTarget: .clipboard, workName: "A")
        let two = try pocket.hold(captureID: b.id, note: "two", intendedTarget: .clipboard, workName: "A")
        let other = try pocket.hold(captureID: c.id, note: nil, intendedTarget: .clipboard, workName: "B")
        check(try pocket.stack().first?.workName == "A", "hold preserves work intent")
        let shelf = PocketModel()
        var complete: ((Bool) -> Void)?
        var batches = 0
        shelf.configure(store: pocket, onDeliver: { items, _, done in
            batches += 1
            check(items.map { $0.0.id } == [one.id, two.id], "selection retains hold order")
            complete = done
        })
        shelf.reload()
        shelf.toggle(two.id)
        shelf.toggle(one.id)
        shelf.deliverSelection()
        shelf.deliverSelection()
        check(batches == 1 && shelf.count == 3, "pending handoff stays visible; duplicate press ignored")
        complete?(false)
        check(shelf.selectedIDs.count == 2 && shelf.error != nil, "failure preserves selection")
        shelf.toggle(other.id)
        check(shelf.hasMixedDestinations && !shelf.canDeliver, "same app, different works cannot be mixed")
        shelf.toggle(other.id)
        shelf.deliverSelection()
        complete?(true)
        check(shelf.items.map { $0.0.id } == [other.id], "success removes only selected items")
        check(try captures.count() == 3, "original captures survive handoff")
        try captures.setUserNote("saved note", captureID: a.id)
        check(try captures.fetch(id: a.id)?.userNote == "saved note", "note survives cancellation")
        let handoff = Handoff(items: [.init(capture: a, note: "one"), .init(capture: b, note: "two")])
        check(handoff.markdown.contains("one") && handoff.markdown.hasSuffix("two\n"), "one payload includes both notes")
        check(handoff.claudeTrigger.contains(a.id) && handoff.claudeTrigger.contains(b.id), "one trigger references both captures")
        check(DeliveryStatus.prepared.displayName == "Prepared · awaiting your send", "draft is not agent completion")
        check(DeliveryStatus.copied.displayName == "Copied", "copy receipt is explicit")
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
    print("== Claude Desktop MCP configuration merge ==")
    do {
        let original = Data(#"{"theme":"dark","mcpServers":{"other":{"command":"other","env":{"TOKEN":"fixture"}}}}"#.utf8)
        let data = try MCPRegistrationConfig.updating(original, name: "beamhop", command: "helper", arguments: ["--db", "/test/db"])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = json["mcpServers"] as! [String: [String: Any]]
        check(json["theme"] as? String == "dark", "unrelated config keys preserved")
        check(servers["other"]?["command"] as? String == "other", "other MCP servers preserved")
        check((servers["other"]?["env"] as? [String: String])?["TOKEN"] == "fixture", "other server environment preserved")
        check(servers["beamhop"]?["args"] as? [String] == ["--db", "/test/db"], "new server arguments installed")
        for text in ["not JSON", "[]", #"{"mcpServers":null}"#, #"{"mcpServers":[]}"#, #"{"mcpServers":"private"}"#] {
            do {
                _ = try MCPRegistrationConfig.updating(Data(text.utf8), name: "beamhop", command: "helper", arguments: [])
                check(false, "malformed existing config rejected")
            } catch { check(true, "malformed existing config rejected without overwrite") }
        }
        let first = try MCPRegistrationConfig.updating(nil, name: "beamhop", command: "old", arguments: [])
        let second = try MCPRegistrationConfig.updating(first, name: "beamhop", command: "new", arguments: [])
        let updated = try JSONSerialization.jsonObject(with: second) as! [String: Any]
        check((updated["mcpServers"] as? [String: [String: Any]])?["beamhop"]?["command"] as? String == "new", "existing beamhop entry can be updated")
    }

    print("== Trial build provenance + privacy report ==")
    do {
        let build = BuildInfo(appVersion: "0.1.0", buildNumber: "7",
                              buildID: "f0ab1c2d-1234-4321-abcd-123456789abc",
                              commit: String(repeating: "a", count: 40), sourceDirty: true,
                              sourceFingerprint: String(repeating: "b", count: 64),
                              builtAtUTC: "2026-10-21T01:02:03Z", configuration: "release",
                              architecture: "arm64", swiftVersion: "6.4.0", signing: .adhoc)
        check(try JSONDecoder().decode(BuildInfo.self, from: JSONEncoder().encode(build)) == build, "provenance round-trips")
        check(build.shortCommit == "aaaaaaa" && build.summary.contains("0.1.0 (7)"), "version and commit display")
        check(BuildInfo().sourceDirty == nil && BuildInfo().shortCommit == "unknown", "missing provenance is unknown, not clean")
        check(BuildInfo(sourceDirty: true).sourceLabel == L10n.s("Local changes"), "dirty source label")
        check(BuildInfo(sourceDirty: false).sourceLabel == L10n.s("Clean build inputs"), "clean source label")
        check(BuildInfo().sourceLabel == L10n.s("Source state unavailable"), "unknown source label")
        let unsafe = """
        {"schema_version":1,"app_version":"0.1.0","build_number":"1","build_id":"/Users/private/token",
        "commit":"secret@example.com","source_dirty":true,"source_fingerprint":"https://private.invalid",
        "built_at_utc":"private note","configuration":"/Users/private","architecture":"device-serial",
        "swift_version":"SECRET","signing":"adhoc","notes":"TOP_SECRET","environment":{"token":"TOKEN_SECRET"}}
        """
        let filtered = try JSONDecoder().decode(BuildInfo.self, from: Data(unsafe.utf8))
        check(filtered.commit == "unknown" && filtered.buildID == "unknown" && filtered.sourceFingerprint == "unknown", "untrusted manifest fields filtered")
        let report = DiagnosticReport(build: filtered, macOSVersion: "/Users/private", runtimeArchitecture: "serial",
            checks: [.init(id: .hotkeys, status: .fail), .init(id: .accessibility, status: .ok), .init(id: .hotkeys, status: .ok)])
        let data = try report.jsonData()
        let json = String(decoding: data, as: UTF8.self)
        check(report.macOSVersion == "unknown" && report.runtimeArchitecture == "unknown", "system fields cannot carry arbitrary text")
        check(report.checks.map(\.id) == [.accessibility, .hotkeys], "known status IDs only, stable order, no duplicates")
        check(data == (try report.jsonData()), "preview and export bytes deterministic")
        for secret in ["/Users/private", "secret@example", "private.invalid", "private note", "device-serial", "TOP_SECRET", "TOKEN_SECRET"] {
            check(!json.contains(secret), "private sentinel excluded: \(secret)")
        }
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        check(Set(object.keys) == Set(["schema_version", "build", "macos_version", "runtime_architecture", "checks", "privacy"]), "report schema has only allowlisted fields")
        do {
            _ = try JSONDecoder().decode(BuildInfo.self, from: Data("{\"schema_version\":2}".utf8))
            check(false, "unsupported provenance rejected")
        } catch { check(true, "unsupported provenance rejected") }
        for value in ["0.1.0\nSECRET", "1.0 token", "../1", "", String(repeating: "1", count: 200)] {
            check(BuildInfo(appVersion: value).appVersion == "unknown", "invalid version rejected")
        }
    }
} catch {
    print("EXCEPTION: \(error)")
    failures += 1
}


do {
    print("== Inline Hop draft, Pocket and receipt safety ==")
    let (db, path) = try freshDB()
    defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
    let cap = sample(selectedText: "immutable original")
    let model = CapturePanelModel(capture: cap, initialTarget: .kimiWork,
        onConfirm: { _, _ in check(false, "attachment must block handoff") }, onCancel: {})
    model.materials[0].text = "edited <>&"
    model.additionalText = "independent addition"
    model.note = "/review\nLiteral instruction"
    let first = model.snapshot
    check(first.materials.count == 2, "inline addition is included without Done")
    check(first.materials[0].original == cap, "original capture is immutable")
    check(first.outgoingText.hasPrefix(model.note) && first.outgoingText.contains("edited <>&")
          && !first.outgoingText.contains("immutable original"), "literal prompt and edited text only")
    let h = Handoff(items: [.init(capture: cap)], editedText: first.outgoingText)
    check(h.markdown == first.outgoingText && h.claudeTrigger == first.outgoingText, "MCP trigger cannot silently restore original")
    model.pendingImportCount = 1
    check(!model.canConfirm, "handoff cannot outrun an attachment import")
    model.confirm()
    model.pendingImportCount = 0
    model.materials.append(HopMaterial(name: "file.png", path: "/local/file.png", image: true, bytes: 10))
    check(!model.canConfirm && model.snapshot.textFallback.contains("file.png"), "unsupported files block, copy names missing attachments")
    model.confirm()
    model.usesProjectContext = true
    model.workName = "Project A"
    model.chooseTool(.clipboard)
    check(model.workName == "Project A", "switching app keeps project context")
    model.chooseTool(nil)
    check(model.confirmLabel == "Save local draft", "local draft action names what it saves")
    let library = try HopLibrary(db)
    let second = HopDraft(materials: [HopMaterial(text: "second")], route: .init(target: .clipboard, project: "B"))
    try library.start(first); try library.hold(first); try library.start(second); try library.restore(first.id)
    check(library.state.active == first && library.state.pocket == [second], "restore protects even prompt-free current material")
    try library.addMaterials(from: second)
    check(library.state.active?.route == first.route && library.state.active?.instruction == first.instruction
          && library.state.pocket == [second], "copy materials preserves both routes and original saved batch")
    let before = library.state.active!
    let record = try library.begin(before)
    var newer = before; newer.materials[0].text = "newer"
    try library.saveActive(newer); try library.finish(record.id, status: .prepared)
    check(library.state.active == newer, "late completion cannot consume newer edit")
    try library.recover(library.state.records[0])
    check(library.state.pocket.contains(newer) && library.state.active?.materials == before.materials, "recovery protects input and uses frozen backup")
    try library.remember(.init(target: .kimiWork, project: "A"))
    try library.remember(.init(target: .chatgptDesktop, project: "A"))
    check(library.state.routes.count == 2, "one project retains multiple applications")
    let reopened = try HopLibrary(db)
    check(reopened.state == library.state, "all drafts, routes and records survive restart")
    let pending = try reopened.begin(reopened.state.active!)
    let interrupted = try HopLibrary(db)
    check(interrupted.state.records.first { $0.id == pending.id }?.status == .failed
          && interrupted.state.records.last?.detail?.contains("unknown") == true, "interrupted handoff never becomes false success or automatic retry")
} catch { print("HOP DRAFT EXCEPTION: \(error)"); failures += 1 }

do {
    print("== PR #8: exact snapshot completion and atomic receipt ==")
    let (db, path) = try freshDB()
    defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
    let library = try HopLibrary(db)
    for parked in [false, true] {
        for edited in [false, true] {
            for status in [HopRecord.Status.prepared, .copied, .failed] {
                let draft = HopDraft(materials: [HopMaterial(text: "snapshot")])
                try library.start(draft)
                let record = try library.begin(draft)
                var current = draft
                if edited { current.instruction = "new instruction"; try library.saveActive(current) }
                let next = HopDraft(materials: [HopMaterial(text: "new capture")])
                if parked { try library.start(next) }
                try library.finish(record.id, status: status)
                let keep = edited || status == .failed
                check(parked ? library.state.active == next && library.state.pocket.contains(current) == keep
                             : library.state.active == (keep ? current : nil),
                      "completion protects edits/failure: parked=\(parked), edited=\(edited), status=\(status)")
                check(library.state.records.last?.draft == draft && library.state.records.last?.status == status,
                      "frozen handoff backup and status survive completion")
            }
        }
    }
    check(try HopLibrary(db).state == library.state, "completion state survives restart")
    let draft = HopDraft(materials: [HopMaterial(text: "keep on write failure")])
    try library.start(draft)
    let record = try library.begin(draft)
    try library.start(HopDraft(materials: [HopMaterial(text: "new capture")]))
    let before = library.state
    let payload = try db.queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM hop_state WHERE id = 1") }
    try db.queue.write { try $0.execute(sql: "CREATE TRIGGER fail_receipt BEFORE UPDATE ON hop_records BEGIN SELECT RAISE(ABORT, 'fixture failure'); END") }
    do {
        try library.finish(record.id, status: .prepared)
        check(false, "receipt write must fail")
    } catch { check(true, "receipt write failure propagated") }
    check(library.state == before, "failed receipt does not publish consumption")
    check(try db.queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM hop_state WHERE id = 1") } == payload,
          "failed receipt rolls back draft document")
    try db.queue.write { try $0.execute(sql: "DROP TRIGGER fail_receipt") }
    try library.finish(record.id, status: .prepared)
    let reopened = try HopLibrary(db)
    check(!library.state.pocket.contains(draft) && reopened.state == library.state, "retry commits receipt and exact consumption together")
} catch { print("HOP COMPLETION EXCEPTION: \(error)"); failures += 1 }

do {
    print("== PR #8: legacy backup migration and editor write isolation ==")
    let (db, path) = try freshDB()
    defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
    var legacy = HopLibrary.State()
    legacy.active = HopDraft(materials: [HopMaterial(text: "editable")])
    legacy.pocket = [HopDraft(materials: [HopMaterial(text: "parked")])]
    legacy.projects = ["Project A"]
    legacy.routes = [.init(target: .kimiWork, project: "Project A")]
    legacy.lastRoute = legacy.routes[0]
    legacy.records = (0..<60).map { index in
        HopRecord(draft: HopDraft(materials: [HopMaterial(text: "\(index)" + String(repeating: "large backup", count: 800))]), status: .copied)
    }
    try db.queue.write { sql in
        try sql.execute(sql: "DROP TABLE hop_records")
        try sql.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v9-hop-records'")
        try sql.execute(sql: "INSERT INTO hop_state (id, payload) VALUES (1, ?)", arguments: [try JSONEncoder().encode(legacy)])
    }
    let migrated = try Database(path: path)
    let library = try HopLibrary(migrated)
    check(library.state == legacy, "v8 migration preserves all backups, drafts, routes and order")
    try migrated.queue.write { sql in
        try sql.execute(sql: "CREATE TRIGGER no_history_insert BEFORE INSERT ON hop_records BEGIN SELECT RAISE(ABORT, 'editor rewrote history'); END")
        try sql.execute(sql: "CREATE TRIGGER no_history_update BEFORE UPDATE ON hop_records BEGIN SELECT RAISE(ABORT, 'editor rewrote history'); END")
    }
    var draft = legacy.active!
    for _ in 0..<10 { draft.instruction += "x"; try library.saveActive(draft) }
    let document = try migrated.queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM hop_state WHERE id = 1")! }
    let stored = try JSONDecoder().decode(HopLibrary.State.self, from: document)
    check(document.count < 4_096 && stored.records.isEmpty,
          "editor document excludes large history payloads")
    check(library.state.records == legacy.records, "editing preserves every backup without inserting/updating history")
    check(try HopLibrary(Database(path: path)).state == library.state, "repeated open neither duplicates nor loses migrated history")
} catch { print("HOP MIGRATION EXCEPTION: \(error)"); failures += 1 }

do {
    print("== PR #8: Claude Desktop deployment registration ==")
    for existing in [[], [0], [1], [0, 1]] as [[Int]] {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let urls = MCPRegistrationConfig.desktopURLs(in: support)
        for index in existing {
            try FileManager.default.createDirectory(at: urls[index].deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"theme\":\"variant\(index)\",\"mcpServers\":{\"other\":{\"command\":\"keep\"}}}".utf8).write(to: urls[index])
        }
        try MCPRegistrationConfig.registerDesktop(in: support, name: "beamhop", command: "/fixture/helper", arguments: ["--db", "/fixture/db"])
        for (index, url) in urls.enumerated() {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            let servers = json["mcpServers"] as! [String: [String: Any]]
            check(servers["beamhop"]?["command"] as? String == "/fixture/helper"
                  && servers["beamhop"]?["args"] as? [String] == ["--db", "/fixture/db"], "both deployment configs receive registration")
            if existing.contains(index) {
                check(json["theme"] as? String == "variant\(index)" && servers["other"]?["command"] as? String == "keep",
                      "each existing deployment keeps unrelated configuration")
            }
        }
    }
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: support) }
    let urls = MCPRegistrationConfig.desktopURLs(in: support)
    let original = [Data(#"{"theme":"keep"}"#.utf8), Data("invalid JSON".utf8)]
    for (url, data) in zip(urls, original) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    do {
        try MCPRegistrationConfig.registerDesktop(in: support, name: "beamhop", command: "helper", arguments: [])
        check(false, "malformed deployment must block registration")
    } catch { check(true, "malformed deployment rejected before any write") }
    for (url, data) in zip(urls, original) { check(try Data(contentsOf: url) == data, "both configurations unchanged on parse failure") }
} catch { print("DESKTOP CONFIG EXCEPTION: \(error)"); failures += 1 }

do {
    let pocket = HopPocketRegression()
    try pocket.testCreateEditDuplicateDeleteUndoSurviveRestart()
    try pocket.testBatchFailureRetryAndLateEditPreservation()
    try pocket.testMixedRoutesRequireExplicitChoiceAndFilteringClearsHiddenSelection()
} catch { print("POCKET CRUD EXCEPTION: \(error)"); failures += 1 }

do {
    print("== Pocket HUD chip policy (2026-10-24 UX pass) ==")
    check(PocketHUDPolicy.isVisible(count: 1, hideWhenEmpty: true), "non-empty stack visible (hide-when-empty on)")
    check(PocketHUDPolicy.isVisible(count: 1, hideWhenEmpty: false), "non-empty stack visible (hide-when-empty off)")
    check(!PocketHUDPolicy.isVisible(count: 0, hideWhenEmpty: true), "empty stack hidden by default")
    check(PocketHUDPolicy.isVisible(count: 0, hideWhenEmpty: false), "empty stack stays as launcher when setting off")
    check(!PocketHUDPolicy.isVisible(count: -2, hideWhenEmpty: true), "negative count treated as empty")
    check(PocketHUDPolicy.opacity(idleFade: true, hovered: false) == 0.55, "idle fade faint when enabled + not hovered")
    check(PocketHUDPolicy.opacity(idleFade: true, hovered: true) == 1.0, "hover restores full opacity")
    check(PocketHUDPolicy.opacity(idleFade: false, hovered: false) == 1.0, "fade setting off keeps full opacity")
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let chip = CGSize(width: 200, height: 36)
    let p = CGPoint(x: 1000, y: 100)
    check(PocketHUDPolicy.parseOrigin(PocketHUDPolicy.formatOrigin(p)) == p, "origin round-trips through persistence string")
    check(PocketHUDPolicy.parseOrigin(nil) == nil && PocketHUDPolicy.parseOrigin("abc") == nil
          && PocketHUDPolicy.parseOrigin("1,2,3") == nil && PocketHUDPolicy.parseOrigin("") == nil,
          "malformed persisted origins rejected")
    let clampedFar = PocketHUDPolicy.clampedOrigin(CGPoint(x: 5000, y: 5000), panelSize: chip, visibleFrame: screen)
    check(clampedFar == CGPoint(x: screen.maxX - chip.width, y: screen.maxY - chip.height),
          "off-screen point pulled back inside")
    let clampedNeg = PocketHUDPolicy.clampedOrigin(CGPoint(x: -500, y: -300), panelSize: chip, visibleFrame: screen)
    check(clampedNeg == CGPoint(x: 0, y: 0), "negative origin pulled back inside")
    let tiny = CGRect(x: 0, y: 0, width: 50, height: 20)
    check(PocketHUDPolicy.clampedOrigin(CGPoint(x: 10, y: 10), panelSize: chip, visibleFrame: tiny) == CGPoint(x: 0, y: 0),
          "frame smaller than panel clamps to minX/minY without flipping")
}

do { try runHopReturnRegression() }
catch { check(false, "Hop return regression: \(error)") }

print(failures == 0 ? "\nALL PASS ✅" : "\n\(failures) FAILURE(S) ❌")
exit(failures == 0 ? 0 : 1)
