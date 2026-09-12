import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum AXCaptureError: LocalizedError {
    case permissionDenied
    case protectedApplication(String)
    case secureField
    case noFrontmostApplication
    case timedOut
    case attributeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Beamhop 没有辅助功能权限。请在诊断面板中开启后重试。"
        case .protectedApplication(let name):
            "\(name) 被标记为受保护应用，Beamhop 不会抓取其中的内容。"
        case .secureField:
            "当前焦点是安全输入框。为保护敏感信息，本次未抓取。"
        case .noFrontmostApplication:
            "没有可抓取的前台应用。"
        case .timedOut:
            "辅助功能读取超过 800ms，已停止等待。Capture 仍会保留，可按需附加截图。"
        case .attributeUnavailable(let name):
            "无法读取 \(name)。"
        }
    }
}

private struct AXReadSnapshot: Sendable {
    var windowTitle: String?
    var selectedText: String?
    var url: URL?
    var pathJSON: String?
}

private final class ContinuationRace<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var isResolved = false
    private let continuation: CheckedContinuation<Value, Never>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Value) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        lock.unlock()
        continuation.resume(returning: value)
    }
}

struct AXCaptureService: Sendable {
    static let timeoutNanoseconds: UInt64 = 800_000_000

    private let protectedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.apple.keychainaccess"
    ]

    @MainActor
    func captureFrontmostApplication() async throws -> CaptureRecord {
        guard AXIsProcessTrusted() else { throw AXCaptureError.permissionDenied }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AXCaptureError.noFrontmostApplication
        }

        let bundleID = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? bundleID
        guard !protectedBundleIDs.contains(bundleID) else {
            throw AXCaptureError.protectedApplication(appName)
        }

        let pid = app.processIdentifier
        let appVersion = app.bundleURL
            .flatMap(Bundle.init(url:))?
            .infoDictionary?["CFBundleShortVersionString"] as? String
        let startedAt = ContinuousClock.now
        let result = await readWithTimeout(pid: pid)
        let elapsed = ContinuousClock.now - startedAt
        let duration = Int(elapsed.components.seconds * 1_000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)

        let snapshot = try result.get()
        return CaptureRecord(
            id: Self.makeCaptureID(),
            createdAt: Date(),
            source: .ax,
            appBundleID: bundleID,
            appName: appName,
            windowTitle: snapshot.windowTitle,
            url: snapshot.url,
            selectedText: snapshot.selectedText,
            extractedBody: nil,
            screenshotPath: nil,
            userNote: nil,
            provenance: CaptureProvenance(
                processID: Int(pid),
                appVersion: appVersion,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                beamhopVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                accessibilityTreeSnapshot: snapshot.pathJSON,
                captureMethod: .accessibility,
                extensionVersion: nil,
                isPrivate: false,
                isTruncated: false,
                captureDurationMilliseconds: duration
            )
        )
    }

    private func readWithTimeout(pid: pid_t) async -> Result<AXReadSnapshot, Error> {
        await withCheckedContinuation { continuation in
            let race = ContinuationRace<Result<AXReadSnapshot, Error>>(continuation)
            Task.detached(priority: .userInitiated) {
                do {
                    race.resolve(.success(try Self.readAX(pid: pid)))
                } catch {
                    race.resolve(.failure(error))
                }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: Self.timeoutNanoseconds)
                race.resolve(.failure(AXCaptureError.timedOut))
            }
        }
    }

    private static func readAX(pid: pid_t) throws -> AXReadSnapshot {
        let application = AXUIElementCreateApplication(pid)
        let focused = copyElement(application, kAXFocusedUIElementAttribute as String)
        let window = copyElement(application, kAXFocusedWindowAttribute as String)
        let title: String? = window.flatMap { copyString($0, kAXTitleAttribute as String) }

        guard let focused else {
            return AXReadSnapshot(
                windowTitle: title,
                selectedText: nil,
                url: nil,
                pathJSON: nil
            )
        }

        let role = copyString(focused, kAXRoleAttribute as String)
        let subrole = copyString(focused, kAXSubroleAttribute as String)
        if role == kAXSecureTextFieldSubrole as String
            || subrole == kAXSecureTextFieldSubrole as String {
            throw AXCaptureError.secureField
        }

        let selected = copyString(focused, kAXSelectedTextAttribute as String)
        let url = findURL(startingAt: focused)
        let path = makePathSnapshot(startingAt: focused)
        return AXReadSnapshot(
            windowTitle: title,
            selectedText: selected?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            url: url,
            pathJSON: path
        )
    }

    private static func findURL(startingAt element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let node = current else { break }
            if let value = copyURL(node, "AXURL") ?? copyURL(node, kAXDocumentAttribute as String) {
                return value
            }
            current = copyElement(node, kAXParentAttribute as String)
        }
        return nil
    }

    private static func makePathSnapshot(startingAt element: AXUIElement) -> String? {
        var nodes: [[String: String]] = []
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            var description: [String: String] = [:]
            description["role"] = copyString(node, kAXRoleAttribute as String) ?? "unknown"
            if let subrole = copyString(node, kAXSubroleAttribute as String), !subrole.isEmpty {
                description["subrole"] = subrole
            }
            if let identifier = copyString(node, kAXIdentifierAttribute as String), !identifier.isEmpty {
                description["identifier"] = identifier
            }
            nodes.append(description)
            current = copyElement(node, kAXParentAttribute as String)
        }
        guard JSONSerialization.isValidJSONObject(nodes),
              let data = try? JSONSerialization.data(withJSONObject: nodes.reversed(), options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    private static func makeCaptureID() -> String {
        let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
        let suffix = String((0..<10).compactMap { _ in alphabet.randomElement() })
        return "cap_\(suffix)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
