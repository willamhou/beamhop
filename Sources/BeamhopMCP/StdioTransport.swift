import Foundation

enum StdioFraming {
    case jsonLines
    case contentLength
}

struct StdioMessage {
    let data: Data
    let framing: StdioFraming
}

final class StdioMessageParser {
    private var buffer = Data()
    private static let headerSeparator = Data("\r\n\r\n".utf8)

    func append(_ data: Data) {
        buffer.append(data)
    }

    func next() -> StdioMessage? {
        while buffer.first == 10 || buffer.first == 13 { buffer.removeFirst() }
        guard !buffer.isEmpty else { return nil }

        if buffer.starts(with: Data("Content-Length:".utf8)) {
            guard let separator = buffer.range(of: Self.headerSeparator) else { return nil }
            let headerData = buffer[..<separator.lowerBound]
            guard let headers = String(data: headerData, encoding: .utf8) else {
                buffer.removeSubrange(..<separator.upperBound)
                return next()
            }
            let length = headers
                .components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
            guard let length, length >= 0 else {
                buffer.removeSubrange(..<separator.upperBound)
                return next()
            }
            let bodyStart = separator.upperBound
            guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            let body = Data(buffer[bodyStart..<bodyEnd])
            buffer.removeSubrange(..<bodyEnd)
            return StdioMessage(data: body, framing: .contentLength)
        }

        guard let newline = buffer.firstIndex(of: 10) else { return nil }
        var line = Data(buffer[..<newline])
        buffer.removeSubrange(...newline)
        if line.last == 13 { line.removeLast() }
        guard !line.isEmpty else { return next() }
        return StdioMessage(data: line, framing: .jsonLines)
    }

    func finish() -> StdioMessage? {
        while buffer.first == 10 || buffer.first == 13 { buffer.removeFirst() }
        guard !buffer.isEmpty else { return nil }
        let final = buffer
        buffer.removeAll(keepingCapacity: false)
        return StdioMessage(data: final, framing: .jsonLines)
    }
}

final class MCPStdioTransport {
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let parser = StdioMessageParser()

    init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        errorOutput: FileHandle = .standardError
    ) {
        self.input = input
        self.output = output
        self.errorOutput = errorOutput
    }

    func run(server: MCPServer) {
        while true {
            let chunk = input.readData(ofLength: 4_096)
            if chunk.isEmpty { break }
            parser.append(chunk)
            drain(server: server)
        }
        if let final = parser.finish() { process(final, server: server) }
    }

    private func drain(server: MCPServer) {
        while let message = parser.next() { process(message, server: server) }
    }

    private func process(_ message: StdioMessage, server: MCPServer) {
        guard let response = server.handle(message.data) else { return }
        switch message.framing {
        case .jsonLines:
            output.write(response)
            output.write(Data("\n".utf8))
        case .contentLength:
            output.write(Data("Content-Length: \(response.count)\r\n\r\n".utf8))
            output.write(response)
        }
    }

    func log(_ message: String) {
        errorOutput.write(Data("[beamhop-mcp] \(message)\n".utf8))
    }
}
