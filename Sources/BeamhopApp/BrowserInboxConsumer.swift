import Darwin
import Foundation

enum BrowserInboxError: LocalizedError {
    case fileTooLarge(String)
    case invalidEnvelope(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let name):
            "浏览器交接文件 \(name) 超过 8 MiB，已拒绝读取。"
        case .invalidEnvelope(let reason):
            "浏览器交接 envelope 无效：\(reason)"
        case .invalidPayload(let reason):
            "浏览器 Capture payload 无效：\(reason)"
        }
    }
}

/// Reliable browser -> app handoff consumer. The native host has already reassembled
/// chunks before atomically writing a logical envelope into browser-inbox.
actor BrowserInboxConsumer {
    static let maximumFileBytes = 8 * 1_024 * 1_024
    static let staleClaimSeconds: TimeInterval = 5 * 60

    private let manager = FileManager.default
    private let appInstanceID = UUID().uuidString.lowercased()
    private let directoryURL: URL
    private let incomingName = try! NSRegularExpression(
        pattern: "^[0-9]{13}-[0-9a-f-]{36}\\.json$"
    )

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = support
                .appendingPathComponent("beamhop", isDirectory: true)
                .appendingPathComponent("browser-inbox", isDirectory: true)
        }
    }

    func consumeAvailable(
        persist: @Sendable (CaptureRecord) async throws -> Void
    ) async -> [CaptureRecord] {
        do {
            try ensureDirectory()
            try recoverStaleClaims()
        } catch {
            return []
        }

        let urls = (try? manager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var persisted: [CaptureRecord] = []
        for originalURL in urls
            .filter({ matchesIncomingName($0.lastPathComponent) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let claimedURL = directoryURL.appendingPathComponent(
                ".\(originalURL.lastPathComponent).processing-\(appInstanceID)"
            )
            do {
                try manager.moveItem(at: originalURL, to: claimedURL)
            } catch {
                continue // another process or app instance won the claim
            }

            do {
                let values = try claimedURL.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= Self.maximumFileBytes else {
                    throw BrowserInboxError.fileTooLarge(originalURL.lastPathComponent)
                }
                let capture = try decodeCapture(at: claimedURL)
                try await persist(capture)
                try manager.removeItem(at: claimedURL)
                persisted.append(capture)
            } catch {
                // No DB commit means no acknowledgement. Put the exact logical message back.
                if manager.fileExists(atPath: claimedURL.path),
                   !manager.fileExists(atPath: originalURL.path) {
                    try? manager.moveItem(at: claimedURL, to: originalURL)
                }
            }
        }
        return persisted
    }

    private func ensureDirectory() throws {
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        chmod(directoryURL.path, S_IRWXU)
    }

    private func recoverStaleClaims() throws {
        let urls = try manager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        )
        let now = Date()
        for claimedURL in urls where claimedURL.lastPathComponent.hasPrefix(".") {
            let name = claimedURL.lastPathComponent
            guard let marker = name.range(of: ".processing-", options: .backwards) else { continue }
            let originalName = String(name[name.index(after: name.startIndex)..<marker.lowerBound])
            guard matchesIncomingName(originalName) else { continue }
            let modified = try claimedURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) > Self.staleClaimSeconds else { continue }
            let originalURL = directoryURL.appendingPathComponent(originalName)
            guard !manager.fileExists(atPath: originalURL.path) else { continue }
            try? manager.moveItem(at: claimedURL, to: originalURL)
        }
    }

    private func matchesIncomingName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return incomingName.firstMatch(in: name, range: range) != nil
    }

    private func decodeCapture(at url: URL) throws -> CaptureRecord {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowserInboxError.invalidEnvelope("root 不是 object")
        }
        guard envelope["protocolVersion"] != nil || envelope["protocol_version"] != nil else {
            throw BrowserInboxError.invalidEnvelope("缺少 protocolVersion")
        }
        guard let route = envelope["route"] as? String,
              route == "browser.captureResult" else {
            throw BrowserInboxError.invalidEnvelope("route 不是 capture")
        }
        guard let payload = envelope["payload"] as? [String: Any] else {
            throw BrowserInboxError.invalidPayload("payload 不是 object")
        }

        if payload["ok"] as? Bool == false {
            let error = payload["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "浏览器扩展抓取失败"
            return failureCapture(
                id: stableCaptureID(from: envelope["requestId"] as? String),
                message: message,
                sentAt: decodeDate(envelope["sentAt"] ?? envelope["sent_at"])
            )
        }
        guard let capturePayload = payload["capture"] as? [String: Any] else {
            throw BrowserInboxError.invalidPayload("成功响应缺少 capture object")
        }

        let appName = string(capturePayload, "app", "appName", "app_name") ?? "Browser"
        let bundleID = string(capturePayload, "bundle", "appBundleID", "app_bundle_id", "bundleId", "bundle_id")
            ?? "unknown.browser"
        let selectedText = string(capturePayload, "selectedText", "selected_text")?.nilIfBlank
        let rawBody = string(capturePayload, "extractedBody", "extracted_body", "body", "markdown")?.nilIfBlank
        let body: String?
        if let structured = capturePayload["structured"],
           JSONSerialization.isValidJSONObject(structured),
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            body = [rawBody, "<github_context>\n\(json)\n</github_context>"]
                .compactMap { $0 }.joined(separator: "\n\n")
        } else {
            body = rawBody
        }
        let urlString = string(capturePayload, "url")
        guard selectedText != nil || body != nil || urlString != nil else {
            throw BrowserInboxError.invalidPayload("selectedText、body、url 均为空")
        }
        let sentAt = decodeDate(capturePayload["capturedAt"])
            ?? decodeDate(envelope["sentAt"] ?? envelope["sent_at"])
            ?? Date()
        let duration = integer(capturePayload, "captureDurationMs", "capture_duration_ms") ?? 0
        let pid = Int32(integer(capturePayload, "pid") ?? 0)

        return CaptureRecord(
            id: string(capturePayload, "captureId", "capture_id", "id")
                ?? stableCaptureID(from: envelope["requestId"] as? String),
            createdAt: sentAt,
            source: .browser,
            appBundleID: bundleID,
            appName: appName,
            windowTitle: string(capturePayload, "windowTitle", "window_title", "title"),
            url: urlString.flatMap(URL.init(string:)),
            selectedText: selectedText,
            extractedBody: body,
            screenshotPath: nil,
            userNote: string(capturePayload, "userNote", "user_note"),
            domainHint: string(capturePayload, "domainHint", "domain_hint"),
            provenance: CaptureProvenance(
                processID: Int(pid),
                appVersion: string(capturePayload, "appVersion", "app_version"),
                operatingSystemVersion: string(capturePayload, "osVersion", "os_version")
                    ?? ProcessInfo.processInfo.operatingSystemVersionString,
                beamhopVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "development",
                accessibilityTreeSnapshot: nil,
                captureMethod: .browserExtension,
                extensionVersion: string(capturePayload, "extensionVersion", "extension_version"),
                isPrivate: boolean(capturePayload, "private", "isPrivate", "is_private") ?? false,
                isTruncated: boolean(capturePayload, "truncated") ?? false,
                captureDurationMilliseconds: duration
            )
        )
    }

    private func failureCapture(id: String, message: String, sentAt: Date?) -> CaptureRecord {
        CaptureRecord(
            id: id,
            createdAt: sentAt ?? Date(),
            source: .browser,
            appBundleID: "unknown.browser",
            appName: "Browser Extension",
            windowTitle: "浏览器抓取失败",
            url: nil,
            selectedText: "[浏览器抓取失败] \(message)",
            extractedBody: nil,
            screenshotPath: nil,
            userNote: nil,
            provenance: CaptureProvenance(
                processID: 0,
                appVersion: nil,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                beamhopVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                accessibilityTreeSnapshot: nil,
                captureMethod: .browserExtension,
                extensionVersion: nil,
                isPrivate: false,
                isTruncated: false,
                captureDurationMilliseconds: 0
            )
        )
    }

    private func string(_ object: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
        }
        return nil
    }

    private func integer(_ object: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? NSNumber { return value.intValue }
        }
        return nil
    }

    private func boolean(_ object: [String: Any], _ keys: String...) -> Bool? {
        for key in keys {
            if let value = object[key] as? Bool { return value }
            if let value = object[key] as? NSNumber { return value.boolValue }
        }
        return nil
    }

    private func decodeDate(_ value: Any?) -> Date? {
        if let milliseconds = value as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        if let milliseconds = value as? NSNumber {
            return Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private func makeCaptureID() -> String {
        "cap_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(10))"
    }

    private func stableCaptureID(from requestID: String?) -> String {
        guard let requestID else { return makeCaptureID() }
        let normalized = requestID.lowercased().filter { $0.isHexDigit }
        return normalized.isEmpty ? makeCaptureID() : "cap_browser_\(normalized.prefix(24))"
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
