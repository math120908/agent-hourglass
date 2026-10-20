import Foundation
import GRDB
import Testing
@testable import UsageCore

@Suite struct HistoryStoreTests {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func columns(_ store: HistoryStore, _ table: String) throws -> [String] {
        try store.db.read { db in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String } }
    }

    @Test func schemaMatchesSpec() throws {
        let s = try HistoryStore.inMemory()
        #expect(try columns(s, "sample") == ["account_id", "meter", "ts", "percent", "used", "limit_v", "resets_at"])
        #expect(try columns(s, "sample_hourly") == ["account_id", "meter", "hour", "percent_max", "percent_last", "resets_at_last"])
        #expect(try columns(s, "spend_sample") == ["account_id", "ts", "used_minor", "limit_minor", "currency", "exponent"])
        #expect(try columns(s, "meta") == ["key", "value"])
        let v = try s.db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'schema_version'") }
        #expect(v == "1")
    }

    @Test func walAndIncrementalVacuum() throws {
        let url = try tempDir().appendingPathComponent(HistoryStore.fileName)
        let s = try HistoryStore(url: url)
        let (mode, vac) = try s.db.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"), try Int.fetchOne(db, sql: "PRAGMA auto_vacuum"))
        }
        #expect(mode == "wal")
        #expect(vac == 2)
    }

    @Test func filesAre0600() async throws {
        let url = try HistoryStore.defaultURL(base: tempDir())
        let s = try HistoryStore(url: url)
        try await s.db.write { try $0.execute(sql: "INSERT INTO sample (account_id, meter, ts) VALUES ('a', 'session', 1)") }
        for suffix in ["", "-wal", "-shm"] {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "\(suffix)")
        }
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect((dirAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(s.fileSizeBytes() > 0)
    }

    @Test func deleteAccountRemovesRows() async throws {
        let s = try HistoryStore.inMemory()
        try await s.db.write { db in
            for a in ["claude:A", "claude:B"] {
                try db.execute(sql: "INSERT INTO sample (account_id, meter, ts) VALUES (?, 'session', 1)", arguments: [a])
                try db.execute(sql: "INSERT INTO sample_hourly (account_id, meter, hour) VALUES (?, 'session', 1)", arguments: [a])
                try db.execute(sql: "INSERT INTO spend_sample (account_id, ts) VALUES (?, 1)", arguments: [a])
            }
        }
        try await s.deleteAccount(AccountID(rawValue: "claude:A")!)
        let left = try await s.db.read { db in
            try ["sample", "sample_hourly", "spend_sample"].map {
                try String.fetchAll(db, sql: "SELECT DISTINCT account_id FROM \($0)")
            }
        }
        #expect(left == [["claude:B"], ["claude:B"], ["claude:B"]])
        try await s.deleteAll()
        let n = try await s.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sample") }
        #expect(n == 0)
    }

    @Test func openFailureDegrades() throws {
        let url = try tempDir().appendingPathComponent(HistoryStore.fileName)
        try Data(repeating: 0x5A, count: 8192).write(to: url)
        #expect(throws: (any Error).self) { try HistoryStore(url: url) }
        // Unopenable path (a directory) also throws rather than crashing.
        #expect(throws: (any Error).self) { try HistoryStore(url: tempDir()) }
    }
}
