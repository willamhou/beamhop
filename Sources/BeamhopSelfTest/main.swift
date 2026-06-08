import Foundation
import BeamhopCore

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
        try Data("not a sqlite database".utf8).write(to: url)
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
} catch {
    print("EXCEPTION: \(error)")
    failures += 1
}

print(failures == 0 ? "\nALL PASS ✅" : "\n\(failures) FAILURE(S) ❌")
exit(failures == 0 ? 0 : 1)
