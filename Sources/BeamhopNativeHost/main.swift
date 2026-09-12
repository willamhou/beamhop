import Foundation

let input = FramedInput(handle: .standardInput, maximumLength: browserToHostFrameLimit)
let output = FramedOutput(handle: .standardOutput, maximumLength: hostToBrowserFrameLimit)
let assembler = ChunkAssembler()
let outgoing = OutgoingTransferManager(output: output)
let desktop = DesktopBridge()

func log(_ message: String) {
    FileHandle.standardError.write(Data("[beamhop-native-host] \(message)\n".utf8))
}

func sendError(transferID: String?, requestID: String?, code: String, message: String) {
    var fields: [String: Any] = ["code": code, "message": message]
    if let transferID { fields["transferId"] = transferID }
    if let requestID { fields["requestId"] = requestID }
    try? output.send(controlMessage("transferError", fields))
}

desktop.onMessage = { data in
    do { try outgoing.sendLogicalData(data) }
    catch { log("desktop-to-browser message failed: \(error)") }
}

desktop.onStatus = { delivery, error in
    var fields: [String: Any] = ["delivery": delivery]
    if let error { fields["error"] = error }
    try? output.send(controlMessage("bridgeStatus", fields))
}

outgoing.onFailure = { message, requestID in
    log(message)
    var logical: [String: Any] = [
        "protocolVersion": bridgeProtocolVersion,
        "requestId": requestID ?? UUID().uuidString.lowercased(),
        "route": "bridge.deliveryError",
        "payload": ["code": "BROWSER_ACK_TIMEOUT", "message": message],
        "sentAt": ISO8601DateFormatter().string(from: Date())
    ]
    if requestID == nil { logical["requestId"] = UUID().uuidString.lowercased() }
    if let data = try? jsonData(logical) { _ = desktop.deliver(data) }
}

desktop.start()
try? output.send(controlMessage("bridgeStatus", ["delivery": "queue"]))

let cleanupTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
cleanupTimer.schedule(deadline: .now() + 5, repeating: 5)
cleanupTimer.setEventHandler {
    for expired in assembler.removeExpired() {
        sendError(transferID: expired.transferID, requestID: expired.requestID,
            code: "REASSEMBLY_TIMEOUT", message: "Browser-to-host reassembly timed out; resend with a new transferId")
    }
}
cleanupTimer.resume()

while true {
    do {
        let frame = try input.readFrame()
        let message = try jsonObject(from: frame)
        let type = message["type"] as? String

        switch type {
        case "chunk":
            let transferID = message["transferId"] as? String
            let requestID = message["requestId"] as? String
            let index = message["index"] as? Int
            let result = assembler.accept(message)
            if let transferID, let index {
                try? output.send(controlMessage("chunkAck", ["transferId": transferID, "index": index]))
            }
            switch result {
            case .partial:
                break
            case .complete(let complete):
                let delivery = desktop.deliver(complete.data)
                if delivery == .unavailable {
                    sendError(transferID: complete.transferID, requestID: complete.requestID,
                        code: "QUEUE_WRITE_FAILED", message: "Could not persist the logical message to the browser inbox")
                    break
                }
                var fields: [String: Any] = [
                    "transferId": complete.transferID,
                    "delivery": delivery.rawValue
                ]
                if let id = complete.requestID { fields["requestId"] = id }
                try? output.send(controlMessage("transferComplete", fields))
            case .failure(let code, let details):
                sendError(transferID: transferID, requestID: requestID, code: code, message: details)
            }

        case "chunkAck":
            if let transferID = message["transferId"] as? String,
               let index = message["index"] as? Int {
                outgoing.acknowledge(transferID: transferID, index: index)
            }

        case "transferComplete":
            if let transferID = message["transferId"] as? String { outgoing.complete(transferID: transferID) }

        case "transferError":
            if let transferID = message["transferId"] as? String { outgoing.fail(transferID: transferID) }

        default:
            sendError(transferID: message["transferId"] as? String,
                requestID: message["requestId"] as? String,
                code: "UNKNOWN_MESSAGE_TYPE", message: "Expected chunk or transfer control message")
        }
    } catch NativeHostError.endOfStream {
        break
    } catch {
        log("input error: \(error)")
        sendError(transferID: nil, requestID: nil, code: "INVALID_NATIVE_FRAME", message: String(describing: error))
    }
}

cleanupTimer.cancel()
desktop.stop()
