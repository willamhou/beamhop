import XCTest
import GRDB
@testable import BeamhopCore

final class HopLibraryRegressionTests: XCTestCase {
    private func withDatabase(_ body: (BeamhopCore.Database, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite")
        try body(Database(path: path), path)
    }

    func testCompletionConsumesOnlySuccessfulUnchangedActiveOrParkedSnapshot() throws {
        try withDatabase { db, _ in
            let library = try HopLibrary(db)
            for parked in [false, true] {
                for edited in [false, true] {
                    for status in [HopRecord.Status.prepared, .copied, .failed] {
                        let draft = HopDraft(materials: [HopMaterial(text: "snapshot")])
                        try library.start(draft)
                        let record = try library.begin(draft)
                        var current = draft
                        if edited { current.instruction = "new instruction"; try library.saveActive(current) }
                        let next = HopDraft(materials: [HopMaterial(text: "new capture")])
                        if parked { try library.start(next) }
                        try library.finish(record.id, status: status)
                        let shouldKeep = edited || status == .failed
                        if parked {
                            XCTAssertEqual(library.state.active, next)
                            XCTAssertEqual(library.state.pocket.contains(current), shouldKeep)
                        } else {
                            XCTAssertEqual(library.state.active, shouldKeep ? current : nil)
                        }
                        XCTAssertEqual(library.state.records.last?.draft, draft)
                        XCTAssertEqual(library.state.records.last?.status, status)
                    }
                }
            }
            XCTAssertEqual(try HopLibrary(db).state, library.state)
        }
    }

    func testLegacyHistoryMigratesOnceAndEditingDoesNotRewriteHistory() throws {
        try withDatabase { db, path in
            var legacy = HopLibrary.State()
            legacy.active = HopDraft(materials: [HopMaterial(text: "editable")])
            legacy.pocket = [HopDraft(materials: [HopMaterial(text: "parked")])]
            legacy.projects = ["Project A"]
            legacy.routes = [.init(target: .kimiWork, project: "Project A")]
            legacy.lastRoute = legacy.routes[0]
            legacy.records = (0..<60).map { index in
                HopRecord(draft: HopDraft(materials: [HopMaterial(text: "\(index)" + String(repeating: "large backup", count: 800))]), status: .copied)
            }
            try db.queue.write { sql in
                try sql.execute(sql: "DROP TABLE hop_records")
                try sql.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v9-hop-records'")
                try sql.execute(sql: "INSERT INTO hop_state (id, payload) VALUES (1, ?)", arguments: [try JSONEncoder().encode(legacy)])
            }
            let migrated = try Database(path: path)
            let library = try HopLibrary(migrated)
            XCTAssertEqual(library.state, legacy)
            try migrated.queue.write { sql in
                try sql.execute(sql: "CREATE TRIGGER no_history_insert BEFORE INSERT ON hop_records BEGIN SELECT RAISE(ABORT, 'editor rewrote history'); END")
                try sql.execute(sql: "CREATE TRIGGER no_history_update BEFORE UPDATE ON hop_records BEGIN SELECT RAISE(ABORT, 'editor rewrote history'); END")
            }
            var draft = legacy.active!
            for _ in 0..<10 { draft.instruction += "x"; try library.saveActive(draft) }
            let document = try migrated.queue.read { sql in
                try XCTUnwrap(Data.fetchOne(sql, sql: "SELECT payload FROM hop_state WHERE id = 1"))
            }
            XCTAssertLessThan(document.count, 4_096)
            XCTAssertTrue(try JSONDecoder().decode(HopLibrary.State.self, from: document).records.isEmpty)
            XCTAssertEqual(library.state.records, legacy.records)
            XCTAssertEqual(try HopLibrary(Database(path: path)).state, library.state)
        }
    }

    func testReceiptWriteFailureRollsBackDraftConsumption() throws {
        try withDatabase { db, _ in
            let library = try HopLibrary(db)
            let draft = HopDraft(materials: [HopMaterial(text: "keep me")])
            try library.start(draft)
            let record = try library.begin(draft)
            try library.start(HopDraft(materials: [HopMaterial(text: "new capture")]))
            let before = library.state
            let payload = try db.queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM hop_state WHERE id = 1") }
            try db.queue.write { sql in
                try sql.execute(sql: "CREATE TRIGGER fail_receipt BEFORE UPDATE ON hop_records BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
            }
            XCTAssertThrowsError(try library.finish(record.id, status: .prepared))
            XCTAssertEqual(library.state, before)
            XCTAssertEqual(try db.queue.read { try Data.fetchOne($0, sql: "SELECT payload FROM hop_state WHERE id = 1") }, payload)
            try db.queue.write { try $0.execute(sql: "DROP TRIGGER fail_receipt") }
            try library.finish(record.id, status: .prepared)
            XCTAssertFalse(library.state.pocket.contains(draft))
            XCTAssertEqual(try HopLibrary(db).state, library.state)
        }
    }
}
