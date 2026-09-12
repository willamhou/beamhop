import AppKit
import SwiftUI

/// Compatibility Matrix (spec §12.5): what we MEASURED on real hardware in Week 0, shipped as
/// data. The canonical evidence file is spike/compatibility-matrix-v0.json; a copy is bundled as
/// a SwiftPM resource. Per-app AX support here is the S6 measured strategy, not aspiration.
enum CompatibilityConfidence: String {
    case verified, limited, unverified, unknown

    var symbol: String {
        switch self {
        case .verified: "✅"
        case .limited: "🟡"
        case .unverified: "⚠️"
        case .unknown: "—"
        }
    }

    static func from(status: String?) -> CompatibilityConfidence {
        guard let s = status?.lowercased() else { return .unknown }
        if s == "pass" || s.contains("confirmed") { return .verified }
        if s.contains("partial") || s.contains("limited") || s.contains("conditional")
            || s.contains("likely") { return .limited }
        return .unverified
    }
}

struct CompatibilityRecord: Identifiable {
    var id: String
    var title: String
    var installedVersion: String?
    var testedVersions: [String]
    var confidence: CompatibilityConfidence
    var detail: String
}

struct CompatibilitySnapshot {
    var generatedAt: String?
    var records: [CompatibilityRecord]
}

enum CompatibilityMatrixLoader {
    /// Bundle.module (packaged app / swift build) first, then repo-relative (bare checkout).
    static func load() -> CompatibilitySnapshot {
        let urls = [
            Bundle.module.url(forResource: "compatibility-matrix-v0", withExtension: "json", subdirectory: "Resources"),
            Bundle.module.url(forResource: "compatibility-matrix-v0", withExtension: "json"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("spike/compatibility-matrix-v0.json"),
        ].compactMap { $0 }

        guard let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let root = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            return CompatibilitySnapshot(generatedAt: nil, records: [
                CompatibilityRecord(id: "missing", title: "兼容矩阵缺失",
                                    installedVersion: nil, testedVersions: [], confidence: .unknown,
                                    detail: "未找到 compatibility-matrix-v0.json;失败时一律走剪贴板降级"),
            ])
        }
        return decode(root: root, generatedAt: root["generated_at"] as? String)
    }

    private static func decode(root: [String: Any], generatedAt: String?) -> CompatibilitySnapshot {
        var records: [CompatibilityRecord] = []

        if let v = root["claude_code"] as? [String: Any] {
            let ver = v["cli_version"] as? String
            records.append(CompatibilityRecord(
                id: "claude_code", title: "Claude Code", installedVersion: ver,
                testedVersions: ver.map { [$0] } ?? [],
                confidence: .from(status: v["status"] as? String),
                detail: v["mcp_add_command"] as? String ?? "MCP 注册命令未记录"))
        }

        if let v = root["claude_cowork"] as? [String: Any] {
            let ver = v["version_tested"] as? String
            let mechanisms = (v["connector_mechanisms"] as? [String])?.joined(separator: " · ")
            records.append(CompatibilityRecord(
                id: "claude_cowork", title: "Claude Cowork",
                installedVersion: installedVersion(bundleID: v["bundle_id"] as? String ?? "com.anthropic.claudefordesktop"),
                testedVersions: ver.map { [$0] } ?? [],
                confidence: .from(status: v["status"] as? String),
                detail: mechanisms ?? "Connector 机制未记录;应用内投递走剪贴板降级"))
        }

        if let v = root["chatgpt_desktop"] as? [String: Any] {
            let versions = v["versions_tested"] as? [String] ?? []
            let installed = installedVersion(bundleID: v["bundle_id"] as? String ?? "com.openai.chat")
            let tested = installed.map { versions.contains($0) } == true
            records.append(CompatibilityRecord(
                id: "chatgpt_desktop", title: "ChatGPT Desktop", installedVersion: installed,
                testedVersions: versions,
                confidence: tested ? .verified : (versions.isEmpty ? .unknown : .unverified),
                detail: "AX opt-in 后 set-value 注入(\(v["inject_method"] as? String ?? "S3 实测"));不自动发送"))
        }

        if let browser = root["browser_extension"] as? [String: Any] {
            let round = browser["native_messaging_roundtrip_ms"] as? [String: Any]
            let median = round?["median"].map { "\($0)" } ?? "?"
            for key in ["chrome", "arc", "brave", "edge"] {
                // chrome is {version,status}; the rest are plain status strings (S4 evidence).
                let entry = browser[key] as? [String: Any]
                let status = entry?["status"] as? String ?? browser[key] as? String
                records.append(CompatibilityRecord(
                    id: "browser_\(key)", title: "\(key.capitalized) 扩展",
                    installedVersion: nil, testedVersions: [],
                    confidence: .from(status: status),
                    detail: key == "chrome" ? "native messaging 实测往返中位 \(median)ms;>1MB 必须分片" : (status ?? "未测试")))
            }
        }

        if let apps = root["ax_apps"] as? [String: Any] {
            for bundleID in apps.keys.sorted() where !bundleID.hasPrefix("_") {
                guard let v = apps[bundleID] as? [String: Any] else { continue }
                let sel = v["selected_text"] as? String ?? "?"
                let via = v["via"] as? String
                let note = v["note"] as? String
                records.append(CompatibilityRecord(
                    id: "ax_\(bundleID)", title: bundleID,
                    installedVersion: installedVersion(bundleID: bundleID),
                    testedVersions: [],
                    confidence: .from(status: v["status"] as? String),
                    detail: "选中文本: \(sel)\(via.map { " · \($0)" } ?? "")\(note.map { " · \($0)" } ?? "")"))
            }
        }

        return CompatibilitySnapshot(generatedAt: generatedAt, records: records)
    }

    private static func installedVersion(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let b = Bundle(url: url) else { return nil }
        return b.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

/// Independent window following the DiagnosticsWindow pattern (S5: hide, don't destroy).
final class CompatibilityWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Beamhop 兼容性"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: CompatibilityView(snapshot: CompatibilityMatrixLoader.load()))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct CompatibilityView: View {
    let snapshot: CompatibilitySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compatibility Matrix").font(.headline)
                Spacer()
                if let at = snapshot.generatedAt {
                    Text("实测于 \(at)").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding([.top, .horizontal], 16)
            Text("Week 0 真机实测数据。未验证的目标会自动降级到剪贴板,不会静默失败。")
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(snapshot.records) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Text(r.confidence.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(r.title).fontWeight(.medium)
                                    if let v = r.installedVersion {
                                        Text("本机 \(v)").font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text(r.detail).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}
