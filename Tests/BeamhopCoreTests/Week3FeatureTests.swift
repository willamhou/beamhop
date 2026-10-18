import XCTest
import Foundation
@testable import BeamhopCore

/// Week 3 feature coverage — mirrors the Week 3 sections of Sources/BeamhopSelfTest/main.swift
/// (XCTest-free runner used under Command Line Tools). Run with `swift test` once the full
/// Xcode license is accepted; until then `BeamhopSelfTest` is the executable gate in CI/local.
final class Week3FeatureTests: XCTestCase {

    // MARK: DuplicateGate (W3-4: <500ms same-window re-press is swallowed)

    func testDuplicateGateBasics() {
        var gate = DuplicateGate()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Doc", at: t0))
        XCTAssertTrue(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Doc", at: t0.addingTimeInterval(0.3)))
        XCTAssertFalse(gate.isDuplicate(bundleID: "com.apple.Safari", title: "Other", at: t0.addingTimeInterval(0.4)))
        XCTAssertFalse(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(0.45)))
        XCTAssertTrue(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(0.9)))
        XCTAssertFalse(gate.isDuplicate(bundleID: "com.google.Chrome", title: "Other", at: t0.addingTimeInterval(2.0)))
    }

    func testDuplicateGateResetAndNilTitle() {
        var gate = DuplicateGate()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(gate.isDuplicate(bundleID: "app.a", title: nil, at: t0))
        XCTAssertTrue(gate.isDuplicate(bundleID: "app.a", title: nil, at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(gate.isDuplicate(bundleID: "app.a", title: "Now has title", at: t0.addingTimeInterval(0.2)))
        gate.reset()
        XCTAssertFalse(gate.isDuplicate(bundleID: "app.a", title: nil, at: t0.addingTimeInterval(0.3)))
    }

    // MARK: PanelShortcut (⌘1-4 targets, ⌘0 inbox-only)

    func testPanelShortcutMapping() {
        XCTAssertEqual(PanelShortcut.claudeCode.target, .claudeCode)
        XCTAssertEqual(PanelShortcut.chatgptDesktop.target, .chatgptDesktop)
        XCTAssertEqual(PanelShortcut.cowork.target, .cowork)
        XCTAssertEqual(PanelShortcut.kimiWork.target, .kimiWork)
        XCTAssertNil(PanelShortcut.inboxOnly.target)
        XCTAssertEqual(PanelShortcut.allCases.count, 5)
        XCTAssertEqual(Set(PanelShortcut.allCases.map(\.rawValue)), Set(["0", "1", "2", "3", "4"]))
        XCTAssertEqual(PanelShortcut.kimiWork.badge, "⌘4")
    }

    func testEveryDeliverableTargetHasShortcut() {
        let mapped = Set(PanelShortcut.allCases.compactMap(\.target))
        for t in DeliveryTarget.allCases where t != .clipboard {
            XCTAssertTrue(mapped.contains(t), "target \(t.rawValue) has no panel shortcut")
        }
    }

    // MARK: TargetMemory (panel pre-selects last successful target)

    func testTargetMemory() {
        var m = TargetMemory()
        XCTAssertEqual(m.last, .claudeCode)
        m.markSucceeded(.kimiWork)
        XCTAssertEqual(m.last, .kimiWork)
        m.markSucceeded(.chatgptDesktop)
        XCTAssertEqual(m.last, .chatgptDesktop)
        m.reset()
        XCTAssertNil(m.last)
        var m2 = TargetMemory(default: nil)
        XCTAssertNil(m2.last)
        m2.markSucceeded(.cowork)
        XCTAssertEqual(m2.last, .cowork)
    }

    // MARK: PromptRenderer

    private func sampleCapture() -> Capture {
        Capture(source: .ax, appBundleID: "com.apple.Safari", appName: "Safari",
                windowTitle: "PR #42", url: "https://github.com/a/b/pull/42",
                selectedText: "hello world", pid: 1, captureMethod: "ax")
    }

    func testFullMarkdownWithoutNote() {
        let md = PromptRenderer.fullMarkdown(sampleCapture(), userNote: nil)
        XCTAssertTrue(md.contains("Source: Safari · https://github.com/a/b/pull/42"))
        XCTAssertTrue(md.contains("Title: PR #42"))
        XCTAssertTrue(md.contains("<selected>\nhello world\n</selected>"))
        XCTAssertFalse(md.contains("<body>"))
    }

    func testFullMarkdownWithNote() {
        let plain = PromptRenderer.fullMarkdown(sampleCapture(), userNote: nil)
        let noted = PromptRenderer.fullMarkdown(sampleCapture(), userNote: "总结一下")
        XCTAssertTrue(noted.hasSuffix("\n总结一下\n"))
        XCTAssertEqual(PromptRenderer.fullMarkdown(sampleCapture(), userNote: ""), plain)
    }

    func testFullMarkdownTruncation() {
        let long = PromptRenderer.fullMarkdown(sampleCapture(), userNote: nil, maxBody: 5)
        XCTAssertTrue(long.contains("hello\n…[truncated; full content in Beamhop Inbox]"))
        XCTAssertFalse(long.contains("hello world</selected>"))
    }

    func testClaudeCodeTrigger() {
        let cap = sampleCapture()
        XCTAssertEqual(PromptRenderer.claudeCodeTrigger(cap, userNote: nil),
                       "用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文")
        XCTAssertEqual(PromptRenderer.claudeCodeTrigger(cap, userNote: "重点看竞态"),
                       "用 Beamhop MCP 的 fetch_capture('\(cap.id)') 拿我刚抓的上下文。重点看竞态")
    }

    // MARK: CapturePanelModel presentation + confirm/cancel wiring

    private func panelModel(capture: Capture, initial: DeliveryTarget? = .kimiWork,
                            confirm: @escaping (DeliveryTarget?, String) -> Void = { _, _ in },
                            cancel: @escaping () -> Void = {}) -> CapturePanelModel {
        CapturePanelModel(capture: capture, initialTarget: initial, onConfirm: confirm, onCancel: cancel)
    }

    func testPanelSummaryAndPreview() {
        let cap = Capture(source: .ax, appBundleID: "com.moonshot.kimichat", appName: "Kimi",
                          windowTitle: "Kimi Work", selectedText: String(repeating: "字", count: 25),
                          pid: 1, captureMethod: "ax")
        let m = panelModel(capture: cap)
        XCTAssertEqual(m.summaryLine, "Kimi · Kimi Work · 20 chars")
        XCTAssertEqual(m.previewText, String(repeating: "字", count: 25))
        XCTAssertEqual(m.confirmLabel, "Deliver (Kimi Work)")
    }

    func testPanelConfirmCarriesTargetAndNote() {
        let cap = sampleCapture()
        var confirmed: (DeliveryTarget?, String)?
        var cancelled = false
        let m = panelModel(capture: cap, initial: .kimiWork,
                           confirm: { t, n in confirmed = (t, n) },
                           cancel: { cancelled = true })
        m.note = "总结一下这段"
        m.confirm()
        XCTAssertEqual(confirmed?.0, .kimiWork)
        XCTAssertEqual(confirmed?.1, "总结一下这段")
        XCTAssertFalse(cancelled)
        m.cancel()
        XCTAssertTrue(cancelled)
    }

    func testPanelInboxOnlyConfirm() {
        var confirmed: (DeliveryTarget?, String)?
        let m = panelModel(capture: sampleCapture(), initial: nil,
                           confirm: { t, n in confirmed = (t, n) })
        XCTAssertEqual(m.confirmLabel, "Save to Inbox only")
        m.confirm()
        XCTAssertNil(confirmed?.0)
    }

    func testPanelEmptyCapture() {
        let cap = Capture(source: .ax, appBundleID: "a", appName: "A", pid: 1, captureMethod: "ax")
        let m = panelModel(capture: cap, initial: .cowork)
        XCTAssertNil(m.previewText)
        XCTAssertEqual(m.summaryLine, "A")
        XCTAssertEqual(m.targetLabel(.cowork), "Cowork → clipboard")
        XCTAssertEqual(m.targetLabel(.clipboard), "Clipboard")
    }

    // MARK: DeliveryTarget raw values

    func testKimiWorkRawValue() {
        XCTAssertEqual(DeliveryTarget.kimiWork.rawValue, "kimi_work")
        XCTAssertEqual(DeliveryTarget(rawValue: "kimi_work"), .kimiWork)
        XCTAssertEqual(DeliveryTarget.allCases.count, 5)
        for t in DeliveryTarget.allCases {
            let data = try! JSONEncoder().encode(t)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(t.rawValue)\"")
        }
    }
}
