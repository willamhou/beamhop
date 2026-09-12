import AppKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var captures: [CaptureRecord] = []
    @Published var deliveriesByCaptureID: [String: [DeliveryRecord]] = [:]
    @Published var selectedCaptureID: String?
    @Published var currentDraft: CaptureDraft?
    @Published var isCapturing = false
    @Published var searchQuery = ""
    @Published var lastActionMessage: String?
    @Published var needsFirstRun: Bool

    let compatibility: CompatibilityMatrixStore
    let diagnostics: PermissionDiagnosticsStore

    private let core: AppCoreClient
    private let axCapture = AXCaptureService()
    private let screenshot: any ScreenshotCapturing
    private let browserInbox = BrowserInboxConsumer()
    private let browserBridge = BrowserBridgeSocketServer()
    private let delivery: DeliveryCoordinator
    private var browserPollTask: Task<Void, Never>?

    lazy var windows = AppWindowCoordinator(model: self)

    init(
        core: AppCoreClient = AppCoreClient(),
        screenshot: any ScreenshotCapturing = SystemScreenshotService()
    ) {
        self.core = core
        self.screenshot = screenshot
        let matrix = CompatibilityMatrixStore()
        self.compatibility = matrix
        self.diagnostics = PermissionDiagnosticsStore(compatibility: matrix)
        self.delivery = DeliveryCoordinator(
            core: core,
            pasteboard: ClipboardPasteService(),
            compatibility: matrix
        )
        self.needsFirstRun = !UserDefaults.standard.bool(forKey: "onboarding.completed")
    }

    deinit {
        browserPollTask?.cancel()
    }

    func start() {
        Task {
            await diagnostics.refresh()
            await refreshInbox()
            await consumeBrowserInbox(preferForDraft: false)
        }
        startBrowserInboxPolling()
        browserBridge.start { [weak self] route in
            guard route == "bridge.queueAvailable" else { return }
            Task { @MainActor in
                guard let self else { return }
                _ = await self.consumeBrowserInbox(preferForDraft: false)
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if needsFirstRun {
            windows.showOnboarding()
        }
    }

    func captureAndShow() {
        guard !isCapturing else { return }
        isCapturing = true
        lastActionMessage = nil
        Task {
            defer { isCapturing = false }

            // Drain captures initiated from the extension popup without
            // confusing an older queued result with this hotkey invocation.
            _ = await consumeBrowserInbox(preferForDraft: false)

            if isFrontmostBrowser(), let browserApp = NSWorkspace.shared.frontmostApplication,
               let requestID = try? browserBridge.requestCurrentTab() {
                let browserStartedAt = ContinuousClock.now
                let expectedID = Self.browserCaptureID(requestID: requestID)
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    let received = await consumeBrowserInbox(preferForDraft: true)
                    if var capture = received.first(where: { $0.id == expectedID }) {
                        capture.appBundleID = browserApp.bundleIdentifier ?? capture.appBundleID
                        capture.appName = browserApp.localizedName ?? capture.appName
                        capture.provenance.processID = Int(browserApp.processIdentifier)
                        capture.provenance.appVersion = browserApp.bundleURL
                            .flatMap(Bundle.init(url:))?
                            .infoDictionary?["CFBundleShortVersionString"] as? String
                        let elapsed = ContinuousClock.now - browserStartedAt
                        capture.provenance.captureDurationMilliseconds =
                            Int(elapsed.components.seconds * 1_000)
                            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                        try? await core.updateCapture(capture)
                        replaceCapture(capture)
                        currentDraft = CaptureDraft(capture: capture)
                        windows.showCapturePanel()
                        return
                    }
                }
            }

            do {
                var capture = try await axCapture.captureFrontmostApplication()
                var captureNotice: String?
                if Self.graphicalBundleIDs.contains(capture.appBundleID) {
                    do {
                        capture.screenshotPath = try await screenshot.capture(for: capture).path
                        capture.source = .screenshot
                        capture.provenance.captureMethod = .screenshot
                        captureNotice = "图形 App 已按策略附带当前窗口截图"
                    } catch {
                        captureNotice = "图形 App 截图失败：\(error.localizedDescription)；已保留 AX 元数据"
                    }
                }
                try await core.saveCapture(capture)
                captures.insert(capture, at: 0)
                var draft = CaptureDraft(capture: capture)
                draft.inlineMessage = captureNotice
                currentDraft = draft
                windows.showCapturePanel()
            } catch AXCaptureError.timedOut {
                let capture = makeLimitedCapture(warning: AXCaptureError.timedOut.localizedDescription)
                do {
                    try await core.saveCapture(capture)
                    captures.insert(capture, at: 0)
                    currentDraft = CaptureDraft(capture: capture)
                    windows.showCapturePanel()
                } catch {
                    lastActionMessage = "受限 Capture 保存失败：\(error.localizedDescription)"
                    windows.showDiagnostics()
                }
            } catch {
                lastActionMessage = error.localizedDescription
                windows.showDiagnostics()
            }
        }
    }

    func deliverCurrentDraft() {
        guard var draft = currentDraft, !draft.isDelivering else { return }
        draft.isDelivering = true
        draft.inlineMessage = nil
        currentDraft = draft

        Task {
            var capture = draft.capture
            capture.userNote = draft.note.nilIfBlank
            if draft.includeScreenshot && capture.screenshotPath == nil {
                do {
                    capture.screenshotPath = try await screenshot.capture(for: capture).path
                } catch {
                    draft.inlineMessage = error.localizedDescription
                }
            }
            do {
                try await core.updateCapture(capture)
            } catch {
                draft.isDelivering = false
                draft.inlineMessage = "Capture 保存失败，已停止投递：\(error.localizedDescription)"
                currentDraft = draft
                return
            }
            replaceCapture(capture)

            let receipt = await delivery.deliver(
                capture: capture,
                to: draft.target,
                note: draft.note.nilIfBlank,
                autoSubmit: (draft.target == .claudeCode || draft.target == .claudeCowork)
                    ? true : draft.autoSubmit
            )
            await loadDeliveries(for: capture.id)
            draft.capture = capture
            draft.isDelivering = false
            draft.inlineMessage = receipt.message
            currentDraft = draft
            lastActionMessage = receipt.message

            if receipt.delivered {
                windows.closeCapturePanel()
                currentDraft = nil
            }
        }
    }

    func cancelCurrentDraft() {
        currentDraft = nil
        windows.closeCapturePanel()
    }

    func pasteLatestAtCursor() {
        Task {
            guard let capture = try? await core.latestCapture() else {
                lastActionMessage = "Inbox 里还没有 Capture"
                return
            }
            let receipt = await delivery.pasteLatestAtCurrentCursor(capture)
            lastActionMessage = receipt.message
            await loadDeliveries(for: capture.id)
        }
    }

    func refreshInbox() async {
        do {
            captures = try await core.recentCaptures(limit: 100)
            if selectedCaptureID == nil {
                selectedCaptureID = captures.first?.id
            }
            for capture in captures {
                deliveriesByCaptureID[capture.id] = try? await core.deliveries(for: capture.id)
            }
        } catch {
            lastActionMessage = "Inbox 读取失败：\(error.localizedDescription)"
        }
    }

    func runSearch() {
        Task {
            do {
                captures = try await core.searchCaptures(searchQuery, limit: 100)
                selectedCaptureID = captures.first?.id
            } catch {
                lastActionMessage = "搜索失败：\(error.localizedDescription)"
            }
        }
    }

    func softDeleteSelectedCapture() {
        guard let selectedCaptureID else { return }
        Task {
            do {
                try await core.softDeleteCapture(id: selectedCaptureID)
                captures.removeAll { $0.id == selectedCaptureID }
                self.selectedCaptureID = captures.first?.id
            } catch {
                lastActionMessage = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    func redeliver(_ capture: CaptureRecord, to target: AppDeliveryTarget) {
        currentDraft = CaptureDraft(capture: capture, target: target)
        windows.showCapturePanel()
    }

    func showDemoCapture() {
        Task {
            var demo = CaptureRecord.demo
            demo.id = "cap_demo_\(UUID().uuidString.prefix(6).lowercased())"
            do {
                try await core.saveCapture(demo)
                captures.insert(demo, at: 0)
                currentDraft = CaptureDraft(capture: demo)
                windows.showCapturePanel()
            } catch {
                lastActionMessage = "演示 Capture 保存失败：\(error.localizedDescription)"
                windows.showDiagnostics()
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        needsFirstRun = false
        windows.closeOnboarding()
    }

    func handleHotKey(_ action: GlobalHotKeyAction) {
        switch action {
        case .capture: captureAndShow()
        case .inbox: windows.showInbox()
        case .pasteLatest: pasteLatestAtCursor()
        }
    }

    var selectedCapture: CaptureRecord? {
        guard let selectedCaptureID else { return nil }
        return captures.first { $0.id == selectedCaptureID }
    }

    func latestDelivery(for captureID: String) -> DeliveryRecord? {
        deliveriesByCaptureID[captureID]?.first
    }

    private func startBrowserInboxPolling() {
        browserPollTask?.cancel()
        browserPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                _ = await self.consumeBrowserInbox(preferForDraft: false)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @discardableResult
    private func consumeBrowserInbox(preferForDraft: Bool) async -> [CaptureRecord] {
        let core = self.core
        let received = await browserInbox.consumeAvailable { capture in
            try await core.saveCapture(capture)
        }
        guard !received.isEmpty else { return [] }
        for capture in received.reversed() {
            replaceCapture(capture)
        }
        if !preferForDraft {
            lastActionMessage = "已从浏览器接收 \(received.count) 条 Capture"
        }
        return received
    }

    private func loadDeliveries(for captureID: String) async {
        deliveriesByCaptureID[captureID] = try? await core.deliveries(for: captureID)
    }

    private func replaceCapture(_ capture: CaptureRecord) {
        captures.removeAll { $0.id == capture.id }
        captures.insert(capture, at: 0)
    }

    private func makeLimitedCapture(warning: String) -> CaptureRecord {
        let app = NSWorkspace.shared.frontmostApplication
        return CaptureRecord(
            id: "cap_\(UUID().uuidString.prefix(10).lowercased())",
            createdAt: Date(),
            source: .ax,
            appBundleID: app?.bundleIdentifier ?? "unknown",
            appName: app?.localizedName ?? "Unknown app",
            windowTitle: nil,
            url: nil,
            selectedText: "[抓取未完成] \(warning)",
            extractedBody: nil,
            screenshotPath: nil,
            userNote: nil,
            provenance: CaptureProvenance(
                processID: Int(app?.processIdentifier ?? 0),
                appVersion: nil,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                beamhopVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                accessibilityTreeSnapshot: nil,
                captureMethod: .accessibility,
                extensionVersion: nil,
                isPrivate: false,
                isTruncated: false,
                captureDurationMilliseconds: 800
            )
        )
    }

    private func isFrontmostBrowser() -> Bool {
        let browserBundleIDs: Set<String> = [
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.microsoft.edgemac"
        ]
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return browserBundleIDs.contains(bundleID)
    }

    private static func browserCaptureID(requestID: String) -> String {
        let normalized = requestID.lowercased().filter { $0.isHexDigit }
        return "cap_browser_\(normalized.prefix(24))"
    }

    private static let graphicalBundleIDs: Set<String> = [
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.apple.Preview",
        "com.apple.QuickTimePlayerX"
    ]
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
