import AppKit
@preconcurrency import ApplicationServices
import BeamhopCore
import Foundation
import UserNotifications

enum DeliveryCoordinatorError: LocalizedError {
    case targetNotRunning(String)
    case unverifiedCompatibility(String)
    case inputNotFound(String)
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .targetNotRunning(let app):
            "\(app) 未运行。"
        case .unverifiedCompatibility(let app):
            "当前 \(app) 版本没有经过 Compatibility Matrix 验证。"
        case .inputNotFound(let app):
            "在 \(app) 中找不到可安全粘贴的输入框。"
        case .accessibilityDenied:
            "没有辅助功能权限，无法执行自动粘贴。"
        }
    }
}

struct DeliveryReceipt: Sendable {
    var target: AppDeliveryTarget
    var delivered: Bool
    var fallbackCopied: Bool
    var message: String
}

@MainActor
final class DeliveryCoordinator {
    private let core: AppCoreClient
    private let pasteboard: ClipboardPasteService
    private let compatibility: CompatibilityMatrixStore

    init(
        core: AppCoreClient,
        pasteboard: ClipboardPasteService,
        compatibility: CompatibilityMatrixStore
    ) {
        self.core = core
        self.pasteboard = pasteboard
        self.compatibility = compatibility
    }

    func deliver(
        capture: CaptureRecord,
        to target: AppDeliveryTarget,
        note: String?,
        autoSubmit: Bool
    ) async -> DeliveryReceipt {
        if target == .inboxOnly {
            return DeliveryReceipt(
                target: target,
                delivered: true,
                fallbackCopied: false,
                message: "Capture 已保存在 Inbox"
            )
        }

        let prompt = renderPrompt(capture: capture, target: target, note: note)
        do {
            switch target {
            case .claudeCode:
                guard await IntegrationDiagnosticsService().claudeCodeMCPReady() else {
                    throw DeliveryCoordinatorError.unverifiedCompatibility("Claude Code MCP 注册")
                }
                try await deliverToClaudeCode(prompt, autoSubmit: autoSubmit)
            case .chatGPTDesktop:
                try await deliverToChatGPT(prompt, autoSubmit: autoSubmit)
            case .claudeCowork:
                try await deliverToCowork(prompt, autoSubmit: autoSubmit)
            case .inboxOnly:
                break
            }
            if let coreTarget = target.coreTarget {
                try? await core.recordDelivery(DeliveryRecord(
                captureID: capture.id,
                target: coreTarget,
                deliveredAt: Date(),
                status: .success,
                errorMessage: nil
                ))
            }
            postNotification(title: "已投递到 \(target.title)", body: capture.displayTitle)
            return DeliveryReceipt(
                target: target,
                delivered: true,
                fallbackCopied: false,
                message: "已投递到 \(target.title)"
            )
        } catch {
            return await clipboardFallback(
                capture: capture,
                target: target,
                cause: error
            )
        }
    }

    func pasteLatestAtCurrentCursor(_ capture: CaptureRecord) async -> DeliveryReceipt {
        let prompt = renderPrompt(capture: capture, target: .chatGPTDesktop, note: nil)
        do {
            guard AXIsProcessTrusted() else { throw DeliveryCoordinatorError.accessibilityDenied }
            try await pasteboard.safePaste(text: prompt, autoSubmit: false)
            try? await core.recordDelivery(DeliveryRecord(
                captureID: capture.id,
                target: .clipboard,
                deliveredAt: Date(),
                status: .success,
                errorMessage: nil
            ))
            return DeliveryReceipt(
                target: .chatGPTDesktop,
                delivered: true,
                fallbackCopied: false,
                message: "已粘贴最近一次 Capture"
            )
        } catch {
            return await clipboardFallback(
                capture: capture,
                target: .chatGPTDesktop,
                cause: error
            )
        }
    }

    private func deliverToClaudeCode(_ prompt: String, autoSubmit: Bool) async throws {
        guard AXIsProcessTrusted() else { throw DeliveryCoordinatorError.accessibilityDenied }
        guard Self.isClaudeCodeProcessRunning() else {
            throw DeliveryCoordinatorError.targetNotRunning("Claude Code")
        }
        guard let terminal = TerminalActivityTracker.shared.deliveryTerminal() else {
            throw DeliveryCoordinatorError.targetNotRunning(
                "最近激活的终端（多终端时 Beamhop 不会猜测目标）"
            )
        }
        guard terminal.activate(options: [.activateIgnoringOtherApps]) else {
            throw DeliveryCoordinatorError.targetNotRunning("Claude Code 所在终端")
        }
        try await Task.sleep(nanoseconds: 180_000_000)
        try await pasteboard.safePaste(text: prompt, autoSubmit: autoSubmit)
    }

    private func deliverToChatGPT(_ prompt: String, autoSubmit: Bool) async throws {
        guard compatibility.isVerified("chatgpt_desktop") else {
            throw DeliveryCoordinatorError.unverifiedCompatibility("ChatGPT Desktop")
        }
        guard AXIsProcessTrusted() else { throw DeliveryCoordinatorError.accessibilityDenied }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.openai.chat"
        }) else {
            throw DeliveryCoordinatorError.targetNotRunning("ChatGPT Desktop")
        }
        guard app.activate(options: [.activateIgnoringOtherApps]) else {
            throw DeliveryCoordinatorError.targetNotRunning("ChatGPT Desktop")
        }
        try await Task.sleep(nanoseconds: 180_000_000)

        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let input = AXInputLocator.findTextInput(in: application) else {
            throw DeliveryCoordinatorError.inputNotFound("ChatGPT Desktop")
        }
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await pasteboard.safePaste(text: prompt, autoSubmit: autoSubmit)
    }

    private func deliverToCowork(_ prompt: String, autoSubmit: Bool) async throws {
        guard compatibility.isVerified("claude_cowork") else {
            throw DeliveryCoordinatorError.unverifiedCompatibility("Claude Cowork Connector")
        }
        guard AXIsProcessTrusted() else { throw DeliveryCoordinatorError.accessibilityDenied }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop"
        }) else {
            throw DeliveryCoordinatorError.targetNotRunning("Claude Desktop / Cowork")
        }
        guard app.activate(options: [.activateIgnoringOtherApps]) else {
            throw DeliveryCoordinatorError.targetNotRunning("Claude Desktop / Cowork")
        }
        try await Task.sleep(nanoseconds: 180_000_000)
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let input = AXInputLocator.findTextInput(in: application) else {
            throw DeliveryCoordinatorError.inputNotFound("Claude Desktop / Cowork")
        }
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await pasteboard.safePaste(text: prompt, autoSubmit: autoSubmit)
    }

    private func clipboardFallback(
        capture: CaptureRecord,
        target: AppDeliveryTarget,
        cause: Error
    ) async -> DeliveryReceipt {
        let fallbackPrompt = SelfContainedMarkdownRenderer().render(capture, userNote: capture.userNote)
        let baseReason = (cause as? LocalizedError)?.errorDescription ?? cause.localizedDescription
        let versionSuffix = targetApplicationVersion(target).map { " [target_version=\($0)]" } ?? ""
        let reason = baseReason + versionSuffix
        if let clipboardError = cause as? ClipboardPasteError,
           case .backupFailed = clipboardError {
            let protectedMessage = "自动投递已停止：\(reason) Beamhop 没有改写你的剪贴板。"
            if let coreTarget = target.coreTarget {
                try? await core.recordDelivery(DeliveryRecord(
                    captureID: capture.id,
                    target: coreTarget,
                    deliveredAt: Date(),
                    status: .failed,
                    errorMessage: protectedMessage
                ))
            }
            return DeliveryReceipt(
                target: target,
                delivered: false,
                fallbackCopied: false,
                message: protectedMessage
            )
        }
        do {
            try pasteboard.copyForManualHandoff(fallbackPrompt)
            if let coreTarget = target.coreTarget {
                try? await core.recordDelivery(DeliveryRecord(
                captureID: capture.id,
                target: coreTarget,
                deliveredAt: Date(),
                status: .failed,
                errorMessage: "\(reason) [clipboard_fallback=true]"
                ))
            }
            let message = "自动投递失败：\(reason) 内容已复制，请手动粘贴。"
            postNotification(title: "已复制到剪贴板", body: message)
            return DeliveryReceipt(
                target: target,
                delivered: false,
                fallbackCopied: true,
                message: message
            )
        } catch {
            let fallbackError = "自动投递失败：\(reason)；剪贴板兜底也失败：\(error.localizedDescription)"
            if let coreTarget = target.coreTarget {
                try? await core.recordDelivery(DeliveryRecord(
                captureID: capture.id,
                target: coreTarget,
                deliveredAt: Date(),
                status: .failed,
                errorMessage: fallbackError
                ))
            }
            return DeliveryReceipt(
                target: target,
                delivered: false,
                fallbackCopied: false,
                message: fallbackError
            )
        }
    }

    private func renderPrompt(
        capture: CaptureRecord,
        target: AppDeliveryTarget,
        note: String?
    ) -> String {
        switch target {
        case .claudeCode:
            ClaudeCodeRenderer().render(capture, userNote: note)
        case .claudeCowork:
            ClaudeCoworkRenderer().render(capture, userNote: note)
        case .chatGPTDesktop, .inboxOnly:
            SelfContainedMarkdownRenderer().render(capture, userNote: note)
        }
    }

    private func targetApplicationVersion(_ target: AppDeliveryTarget) -> String? {
        let bundleID: String?
        switch target {
        case .chatGPTDesktop: bundleID = "com.openai.chat"
        case .claudeCowork: bundleID = "com.anthropic.claudefordesktop"
        case .claudeCode, .inboxOnly: bundleID = nil
        }
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private static func isClaudeCodeProcessRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private enum AXInputLocator {
    static func findTextInput(in root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 2_000 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if depth > 14 { continue }
            let role = stringAttribute(element, kAXRoleAttribute as String)
            let subrole = stringAttribute(element, kAXSubroleAttribute as String)
            if (role == kAXTextAreaRole as String || role == kAXTextFieldRole as String),
               subrole != kAXSecureTextFieldSubrole as String {
                return element
            }
            queue.append(contentsOf: children(element).map { ($0, depth + 1) })
        }
        return nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
