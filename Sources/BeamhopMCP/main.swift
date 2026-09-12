import BeamhopCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private func terminate(_ status: Int32) -> Never {
    exit(status)
}

private func databaseURL(arguments: [String]) throws -> URL? {
    guard arguments.count > 1 else { return nil }
    var index = 1
    var result: URL?
    while index < arguments.count {
        switch arguments[index] {
        case "--database":
            guard index + 1 < arguments.count else {
                throw CLIError("--database requires a path")
            }
            result = URL(fileURLWithPath: arguments[index + 1])
            index += 2
        case "--help", "-h":
            FileHandle.standardError.write(Data("Usage: beamhop-mcp [--database /path/to/inbox.sqlite]\n".utf8))
            terminate(0)
        default:
            throw CLIError("Unknown argument: \(arguments[index])")
        }
    }
    return result
}

private struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let transport = MCPStdioTransport()
do {
    let requestedURL = try databaseURL(arguments: CommandLine.arguments)
    let repository = try requestedURL.map { try CaptureRepository(databaseURL: $0) } ?? CaptureRepository()
    if let backup = repository.recoveredDatabaseBackupURL {
        transport.log("Recovered a damaged database; backup preserved at \(backup.path)")
    }
    transport.run(server: MCPServer(repository: repository))
} catch {
    transport.log(String(describing: error))
    terminate(1)
}
