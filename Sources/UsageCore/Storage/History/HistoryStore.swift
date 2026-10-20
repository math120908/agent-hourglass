import Foundation
import GRDB

/// Usage history (spec §8): SQLite WAL, `auto_vacuum = INCREMENTAL`, db/-wal/-shm all 0600.
/// A throwing init means "history unavailable"; callers keep polling without it.
public final class HistoryStore: Sendable {
    public static let fileName = "history.sqlite"

    let db: any DatabaseWriter
    let url: URL?
    let lastRows = LastRowCache()

    /// Opens (creating if needed) the store at `url`. Throws on locked/corrupt files.
    public init(url: URL) throws {
        // Pre-create 0600: SQLite gives -wal/-shm the main file's mode.
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let pool = try DatabasePool(path: url.path, configuration: Self.configuration())
        try HistorySchema.migrator.migrate(pool)
        db = pool
        self.url = url
        Self.tightenSidecars(url)
    }

    private init(writer: any DatabaseWriter) {
        db = writer
        url = nil
    }

    public static func inMemory() throws -> HistoryStore {
        let q = try DatabaseQueue(configuration: configuration())
        try HistorySchema.migrator.migrate(q)
        return HistoryStore(writer: q)
    }

    /// `<AppSupport>/history.sqlite`.
    public static func defaultURL(base: URL? = nil) throws -> URL {
        try AppSupport.directory(base: base).appendingPathComponent(fileName)
    }

    private static func configuration() -> Configuration {
        var c = Configuration()
        c.prepareDatabase { db in
            // Writer only (pool readers are read-only); effective only at creation.
            if !db.configuration.readonly { try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL") }
        }
        return c
    }

    private static func tightenSidecars(_ url: URL) {
        for suffix in ["-wal", "-shm"] {
            chmod(url.path + suffix, 0o600)
        }
    }

    public func deleteAccount(_ id: AccountID) async throws {
        try await db.write { db in
            for table in ["sample", "sample_hourly", "spend_sample"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE account_id = ?", arguments: [id.rawValue])
            }
        }
        lastRows.clear()
    }

    public func deleteAll() async throws {
        try await db.write { db in
            for table in ["sample", "sample_hourly", "spend_sample"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        lastRows.clear()
    }

    /// Main file + WAL size; 0 for in-memory.
    public func fileSizeBytes() -> Int64 {
        guard let url else { return 0 }
        return ["", "-wal"].reduce(Int64(0)) { sum, suffix in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path + suffix)
            return sum + ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }
}
