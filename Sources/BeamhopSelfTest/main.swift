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

// Minimal XCTest-free test runner (CLT has no XCTest). Mirrors StorageTests.
// Exits non-zero on any failure.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") }
    else { print("  ✗ FAIL: \(msg)"); failures += 1 }
}

func freshStore() throws -> (CaptureStore, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("beamhop-selftest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("inbox.sqlite")
    return (CaptureStore(try Database(path: url)), url)
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
        // claude trigger
        let trig = PromptRenderer.claudeCodeTrigger(cap, userNote: nil)
        check(trig == "用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文", "trigger without note")
        let trigNote = PromptRenderer.claudeCodeTrigger(cap, userNote: "重点看竞态")
        check(trigNote == "用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文。重点看竞态", "trigger with note")
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
} catch {
    print("EXCEPTION: \(error)")
    failures += 1
}

print(failures == 0 ? "\nALL PASS ✅" : "\n\(failures) FAILURE(S) ❌")
exit(failures == 0 ? 0 : 1)
