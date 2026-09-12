import BeamhopCore
import Foundation

typealias CaptureRecord = BeamhopCore.Capture
typealias CaptureProvenance = BeamhopCore.CaptureProvenance
typealias CaptureSource = BeamhopCore.CaptureSource
typealias DeliveryRecord = BeamhopCore.Delivery
typealias DeliveryStatus = BeamhopCore.DeliveryStatus

enum AppDeliveryTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case claudeCowork
    case chatGPTDesktop
    case inboxOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeCowork: "Claude Cowork"
        case .chatGPTDesktop: "ChatGPT"
        case .inboxOnly: "仅入 Inbox"
        }
    }

    var shortcutNumber: String {
        switch self {
        case .claudeCode: "1"
        case .claudeCowork: "2"
        case .chatGPTDesktop: "3"
        case .inboxOnly: "0"
        }
    }

    var coreTarget: BeamhopCore.DeliveryTarget? {
        switch self {
        case .claudeCode: .claudeCode
        case .claudeCowork: .claudeCowork
        case .chatGPTDesktop: .chatGPTDesktop
        case .inboxOnly: nil
        }
    }
}

struct CaptureDraft: Identifiable, Sendable {
    var capture: CaptureRecord
    var note: String = ""
    var target: AppDeliveryTarget = .claudeCode
    var includeScreenshot = false
    var autoSubmit = false
    var isDelivering = false
    var inlineMessage: String?

    var id: String { capture.id }
}

struct IntegrationDiagnostic: Identifiable, Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case ready
        case needsAction
        case warning
        case unavailable
        case unknown
    }

    var id: String
    var title: String
    var state: State
    var detail: String
    var recoveryTitle: String?
}

extension BeamhopCore.Capture {
    var previewText: String {
        let candidates = [selectedText, extractedBody]
        return candidates.compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }.first ?? "未抓取到文本内容"
    }

    var displayTitle: String {
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? appName : title
    }

    static var demo: BeamhopCore.Capture {
        BeamhopCore.Capture(
            source: .ax,
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Beamhop 首次抓取示例",
            url: URL(string: "https://example.com/beamhop-demo"),
            selectedText: "这是一条仅保存在本机的演示 Capture。你可以先体验 Inbox，再决定是否连接外部 agent。",
            provenance: CaptureProvenance(
                processID: 0,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                beamhopVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                captureMethod: .manual,
                captureDurationMilliseconds: 0
            )
        )
    }
}
