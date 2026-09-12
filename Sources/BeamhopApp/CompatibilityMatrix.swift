import AppKit
import Foundation
import SwiftUI

enum CompatibilityConfidence: String, Sendable {
    case verified
    case limited
    case unverified
    case unknown

    var label: String {
        switch self {
        case .verified: "verified"
        case .limited: "limited"
        case .unverified: "unverified"
        case .unknown: "unknown"
        }
    }

    var color: Color {
        switch self {
        case .verified: .green
        case .limited: .orange
        case .unverified: .yellow
        case .unknown: .secondary
        }
    }
}

struct CompatibilityRecord: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var installedVersion: String?
    var testedVersions: [String]
    var confidence: CompatibilityConfidence
    var detail: String
}

struct CompatibilityMatrixSnapshot: Sendable {
    var schemaVersion: Int?
    var generatedAt: String?
    var sourceAvailable: Bool
    var sourceDescription: String
    var records: [CompatibilityRecord]
}

struct CompatibilityMatrixLoader {
    private let bundle: Bundle

    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }

    func load() -> CompatibilityMatrixSnapshot {
        guard let url = bundle.url(
            forResource: "compatibility-matrix-v0",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? bundle.url(
            forResource: "compatibility-matrix-v0",
            withExtension: "json"
        ) else {
            return .missing("Bundle.module/Resources/compatibility-matrix-v0.json 不存在")
        }

        do {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .missing("Compatibility Matrix 根节点不是 JSON object")
            }
            return decode(root: root, source: url.lastPathComponent)
        } catch {
            return .missing("Compatibility Matrix 无法读取：\(error.localizedDescription)")
        }
    }

    private func decode(root: [String: Any], source: String) -> CompatibilityMatrixSnapshot {
        var records: [CompatibilityRecord] = []

        if let value = root["chatgpt_desktop"] as? [String: Any] {
            let versions = stringArray(value["versions_tested"] ?? value["tested"])
            let installed = installedVersion(bundleID: value["bundle_id"] as? String ?? "com.openai.chat")
            let status = value["status"] as? String
            let verified = installed.map { versions.contains($0) } == true && isPassing(status)
            records.append(CompatibilityRecord(
                id: "chatgpt_desktop",
                title: "ChatGPT Desktop",
                installedVersion: installed,
                testedVersions: versions,
                confidence: verified ? .verified : (versions.isEmpty ? .unknown : .unverified),
                detail: string(value["ax_input_path"] ?? value["ax_path"])
                    .map { "AX path: \($0)" }
                    ?? "没有已验证的 AX 输入路径"
            ))
        }

        if let value = root["claude_code"] as? [String: Any] {
            let status = value["status"] as? String
            let version = value["cli_version"] as? String
            let versions = stringArray(value["cli_versions_tested"] ?? value["tested"])
            records.append(CompatibilityRecord(
                id: "claude_code",
                title: "Claude Code",
                installedVersion: version,
                testedVersions: version.map { [$0] } ?? versions,
                confidence: isPassing(status) ? .verified : confidence(from: status),
                detail: value["mcp_add_command"] as? String ?? "MCP 注册命令未验证"
            ))
        }

        if let value = root["claude_cowork"] as? [String: Any] {
            let status = value["status"] as? String
            let version = value["version_tested"] as? String
            let versions = version.map { [$0] }
                ?? stringArray(value["versions_tested"] ?? value["tested"])
            let installed = installedVersion(
                bundleID: value["bundle_id"] as? String ?? "com.anthropic.claudefordesktop"
            )
            records.append(CompatibilityRecord(
                id: "claude_cowork",
                title: "Claude Cowork",
                installedVersion: installed,
                testedVersions: versions,
                confidence: isPassing(status) && (versions.isEmpty || installed.map(versions.contains) == true)
                    ? .verified : confidence(from: status),
                detail: value["connector_mechanism"] as? String ?? "Connector 机制未验证，使用剪贴板 handoff"
            ))
        }

        if let browser = root["browser_extension"] as? [String: Any] {
            for key in ["chrome", "arc", "brave", "edge"] {
                let status = browser[key] as? String
                records.append(CompatibilityRecord(
                    id: "browser_\(key)",
                    title: "\(key.capitalized) Extension",
                    installedVersion: nil,
                    testedVersions: [],
                    confidence: confidence(from: status),
                    detail: status ?? "未验证"
                ))
            }
        }

        if let apps = root["ax_apps"] as? [String: Any] {
            for bundleID in apps.keys.sorted() {
                let value = apps[bundleID] as? [String: Any] ?? [:]
                let supports = stringArray(value["supports"])
                let notes = value["notes"] as? String
                let statusConfidence = confidence(from: value["status"] as? String)
                records.append(CompatibilityRecord(
                    id: "ax_\(bundleID)",
                    title: bundleID,
                    installedVersion: installedVersion(bundleID: bundleID),
                    testedVersions: [],
                    confidence: supports.contains("selected_text") ? .verified : statusConfidence,
                    detail: notes?.nilIfBlank ?? "AX: \(supports.joined(separator: ", "))"
                ))
            }
        }

        if records.isEmpty {
            return .missing("Compatibility Matrix 已找到，但没有可展示的目标记录")
        }
        return CompatibilityMatrixSnapshot(
            schemaVersion: root["schema_version"] as? Int,
            generatedAt: root["generated_at"] as? String,
            sourceAvailable: true,
            sourceDescription: source,
            records: records
        )
    }

    private func installedVersion(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func confidence(from status: String?) -> CompatibilityConfidence {
        guard let status = status?.lowercased() else { return .unknown }
        if isPassing(status) { return .verified }
        if status.contains("partial") || status.contains("limited") { return .limited }
        if status.contains("fail") || status.contains("defer") || status.contains("broken") {
            return .unverified
        }
        return .unknown
    }

    private func isPassing(_ status: String?) -> Bool {
        guard let status = status?.lowercased() else { return false }
        return status == "pass" || status == "passed" || status == "verified" || status == "ready"
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    private func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8) else { return nil }
        return encoded
    }
}

@MainActor
final class CompatibilityMatrixStore: ObservableObject {
    @Published private(set) var snapshot: CompatibilityMatrixSnapshot
    private let loader: CompatibilityMatrixLoader

    init(loader: CompatibilityMatrixLoader = CompatibilityMatrixLoader()) {
        self.loader = loader
        self.snapshot = loader.load()
        applyLocalSuccesses()
    }

    func reload() {
        snapshot = loader.load()
        applyLocalSuccesses()
    }

    func isVerified(_ recordID: String) -> Bool {
        snapshot.records.first { $0.id == recordID }?.confidence == .verified
    }

    func markLocalSuccess(recordID: String) {
        guard let record = snapshot.records.first(where: { $0.id == recordID }),
              let version = record.installedVersion else { return }
        UserDefaults.standard.set(version, forKey: "compatibility.localSuccess.\(recordID)")
        applyLocalSuccesses()
    }

    private func applyLocalSuccesses() {
        for index in snapshot.records.indices {
            let record = snapshot.records[index]
            guard let installed = record.installedVersion,
                  UserDefaults.standard.string(
                    forKey: "compatibility.localSuccess.\(record.id)"
                  ) == installed else { continue }
            snapshot.records[index].confidence = .verified
            if !snapshot.records[index].detail.hasPrefix("本机已由用户标记成功。") {
                snapshot.records[index].detail = "本机已由用户标记成功。" + snapshot.records[index].detail
            }
        }
    }
}

private extension CompatibilityMatrixSnapshot {
    static func missing(_ reason: String) -> Self {
        CompatibilityMatrixSnapshot(
            schemaVersion: nil,
            generatedAt: nil,
            sourceAvailable: false,
            sourceDescription: reason,
            records: [
                CompatibilityRecord(
                    id: "claude_code",
                    title: "Claude Code",
                    installedVersion: nil,
                    testedVersions: [],
                    confidence: .unknown,
                    detail: "未验证；失败时使用剪贴板 handoff"
                ),
                CompatibilityRecord(
                    id: "chatgpt_desktop",
                    title: "ChatGPT Desktop",
                    installedVersion: nil,
                    testedVersions: [],
                    confidence: .unverified,
                    detail: "没有 matrix 证据，不执行 AX 自动粘贴"
                ),
                CompatibilityRecord(
                    id: "claude_cowork",
                    title: "Claude Cowork",
                    installedVersion: nil,
                    testedVersions: [],
                    confidence: .unverified,
                    detail: "Connector 未验证，使用剪贴板 handoff"
                )
            ]
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
