import BeamhopCore
import Foundation

/// Serializes App-layer access to the real BeamhopCore SQLite repository while
/// keeping blocking SQLite work off the main actor.
actor AppCoreClient {
    private let repository: CaptureRepository?
    private let startupError: Error?

    init() {
        do {
            repository = try CaptureRepository()
            startupError = nil
        } catch {
            repository = nil
            startupError = error
        }
    }

    func saveCapture(_ capture: CaptureRecord) throws {
        let repository = try requireRepository()
        if try repository.capture(id: capture.id, includeDeleted: true) == nil {
            try repository.insert(capture)
        }
    }

    func updateCapture(_ capture: CaptureRecord) throws {
        try requireRepository().update(capture)
    }

    func recentCaptures(limit: Int) throws -> [CaptureRecord] {
        try requireRepository().recent(limit: limit)
    }

    func searchCaptures(_ query: String, limit: Int) throws -> [CaptureRecord] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            ? try requireRepository().recent(limit: limit)
            : try requireRepository().search(normalized, limit: limit)
    }

    func latestCapture() throws -> CaptureRecord? {
        try requireRepository().latest()
    }

    func softDeleteCapture(id: String) throws {
        _ = try requireRepository().softDelete(id: id)
    }

    func recordDelivery(_ delivery: DeliveryRecord) throws {
        _ = try requireRepository().recordDelivery(delivery)
    }

    func deliveries(for captureID: String) throws -> [DeliveryRecord] {
        try requireRepository().deliveries(for: captureID)
    }

    private func requireRepository() throws -> CaptureRepository {
        if let repository { return repository }
        throw startupError ?? CocoaError(.fileReadUnknown)
    }
}
