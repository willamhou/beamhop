import AppKit
import Foundation

struct IntegrationDiagnosticsService: Sendable {
    private static let browserPaths = [
        "Google/Chrome",
        "Google/Chrome Canary",
        "Chromium",
        "Arc/User Data",
        "BraveSoftware/Brave-Browser",
        "Microsoft Edge"
    ]

    func probe(matrix: CompatibilityMatrixSnapshot) async -> [IntegrationDiagnostic] {
        let system = await Task.detached(priority: .utility) {
            [Self.probeClaudeCode(), Self.probeBrowserManifest()]
        }.value
        var result = system
        result.append(matrixDiagnostic(
            id: "chatgpt-matrix",
            title: "ChatGPT Desktop AX",
            recordID: "chatgpt_desktop",
            matrix: matrix
        ))
        result.append(matrixDiagnostic(
            id: "cowork-matrix",
            title: "Claude Cowork",
            recordID: "claude_cowork",
            matrix: matrix
        ))
        return result
    }

    func claudeCodeMCPReady() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            Self.probeClaudeCode().state == .ready
        }.value
    }

    @MainActor
    func copyClaudeRegistrationCommand() -> Bool {
        guard let command = Self.claudeRegistrationCommand() else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }

    func repairBrowserManifests() throws -> Int {
        guard let hostPath = Self.nativeHostExecutablePath() else { return 0 }
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var repaired = 0
        for relative in Self.browserPaths {
            let manifest = support
                .appendingPathComponent(relative, isDirectory: true)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
                .appendingPathComponent("com.beamhop.bridge.json")
            guard manager.fileExists(atPath: manifest.path),
                  let data = try? Data(contentsOf: manifest),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let origins = json["allowed_origins"] as? [String],
                  !origins.isEmpty else { continue }
            json["name"] = "com.beamhop.bridge"
            json["description"] = "Beamhop browser bridge"
            json["path"] = hostPath
            json["type"] = "stdio"
            let encoded = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try encoded.write(to: manifest, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
            repaired += 1
        }
        return repaired
    }

    private func matrixDiagnostic(
        id: String,
        title: String,
        recordID: String,
        matrix: CompatibilityMatrixSnapshot
    ) -> IntegrationDiagnostic {
        guard let record = matrix.records.first(where: { $0.id == recordID }) else {
            return IntegrationDiagnostic(
                id: id,
                title: title,
                state: .unknown,
                detail: "Compatibility Matrix 没有此目标记录。自动化已禁用。",
                recoveryTitle: "查看 Matrix"
            )
        }
        switch record.confidence {
        case .verified:
            return IntegrationDiagnostic(
                id: id,
                title: title,
                state: .ready,
                detail: "当前版本已在 Compatibility Matrix 验证。",
                recoveryTitle: "查看 Matrix"
            )
        case .limited:
            return IntegrationDiagnostic(
                id: id,
                title: title,
                state: .warning,
                detail: record.detail,
                recoveryTitle: "查看 Matrix"
            )
        case .unverified, .unknown:
            return IntegrationDiagnostic(
                id: id,
                title: title,
                state: .needsAction,
                detail: "\(record.confidence.label)：\(record.detail) 自动投递会降级到剪贴板。",
                recoveryTitle: "查看 Matrix"
            )
        }
    }

    private static func probeClaudeCode() -> IntegrationDiagnostic {
        guard let claude = executable(named: "claude") else {
            return IntegrationDiagnostic(
                id: "claude-code-mcp",
                title: "Claude Code MCP",
                state: .needsAction,
                detail: "PATH 与常见安装目录中没有 claude。安装后可复制精确注册命令。",
                recoveryTitle: "复制注册命令"
            )
        }
        guard mcpExecutablePath() != nil else {
            return IntegrationDiagnostic(
                id: "claude-code-mcp",
                title: "Claude Code MCP",
                state: .needsAction,
                detail: "已找到 \(claude)，但 App 包内缺少 beamhop-mcp，无法生成安全的绝对路径注册命令。",
                recoveryTitle: "重新检查"
            )
        }
        let result = run(executable: claude, arguments: ["mcp", "get", "beamhop"], timeout: 1.5)
        if result.exitCode == 0 {
            return IntegrationDiagnostic(
                id: "claude-code-mcp",
                title: "Claude Code MCP",
                state: .ready,
                detail: "\(claude) 已安装，`claude mcp get beamhop` 检查通过。",
                recoveryTitle: "重新检查"
            )
        }
        let suffix = result.timedOut ? "检查超时。" : "尚未注册或 server 不可启动。"
        return IntegrationDiagnostic(
            id: "claude-code-mcp",
            title: "Claude Code MCP",
            state: .needsAction,
            detail: "找到 \(claude)，但 \(suffix)",
            recoveryTitle: "复制注册命令"
        )
    }

    private static func probeBrowserManifest() -> IntegrationDiagnostic {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var installed = 0
        var invalid: [String] = []
        for relative in browserPaths {
            let manifest = support
                .appendingPathComponent(relative, isDirectory: true)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
                .appendingPathComponent("com.beamhop.bridge.json")
            guard manager.fileExists(atPath: manifest.path) else { continue }
            installed += 1
            guard let data = try? Data(contentsOf: manifest),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == "com.beamhop.bridge",
                  json["type"] as? String == "stdio",
                  let path = json["path"] as? String,
                  path.hasPrefix("/"),
                  manager.isExecutableFile(atPath: path),
                  let origins = json["allowed_origins"] as? [String],
                  !origins.isEmpty,
                  origins.allSatisfy({ $0.hasPrefix("chrome-extension://") && $0.hasSuffix("/") }) else {
                invalid.append(relative)
                continue
            }
        }
        if installed > 0 && invalid.isEmpty {
            return IntegrationDiagnostic(
                id: "chrome-native-host",
                title: "Chrome Native Messaging",
                state: .ready,
                detail: "已验证 \(installed) 份 manifest：host path 可执行，allowed_origins 有效。",
                recoveryTitle: "重新检查"
            )
        }
        if !invalid.isEmpty {
            return IntegrationDiagnostic(
                id: "chrome-native-host",
                title: "Chrome Native Messaging",
                state: .needsAction,
                detail: "manifest 无效：\(invalid.joined(separator: ", "))。可保留已安装扩展 origin 并修复 host path。",
                recoveryTitle: "修复 manifest"
            )
        }
        return IntegrationDiagnostic(
            id: "chrome-native-host",
            title: "Chrome Native Messaging",
            state: .needsAction,
            detail: "没有找到 com.beamhop.bridge.json。请先安装浏览器扩展和 native host。",
            recoveryTitle: "重新检查"
        )
    }

    private static func claudeRegistrationCommand() -> String? {
        guard let mcp = mcpExecutablePath() else { return nil }
        return "claude mcp add --transport stdio --scope user beamhop -- \"\(mcp)\""
    }

    private static func mcpExecutablePath() -> String? {
        siblingExecutable(candidates: ["beamhop-mcp", "BeamhopMCP"])
    }

    private static func nativeHostExecutablePath() -> String? {
        siblingExecutable(candidates: ["beamhop-native-host", "BeamhopNativeHost"])
    }

    private static func siblingExecutable(candidates: [String]) -> String? {
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        return candidates
            .map { directory.appendingPathComponent($0).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func executable(named name: String) -> String? {
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        directories.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> (exitCode: Int32, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
        } catch {
            return (-1, false)
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.25)
            return (-1, true)
        }
        return (process.terminationStatus, false)
    }
}
