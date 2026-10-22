import Foundation
import GRDB
import os

/// Spec §8 maintenance: hourly rollup past the raw window, 2-year hourly retention,
/// weekly incremental vacuum, disk budget. Runs on launch, then on the first tick after 03:00 local each day.
extension HistoryStore {
    public static let hourlyRetention: TimeInterval = 730 * 86400
    public static let shrinkThreshold: Int64 = 100 * 1024 * 1024
    public static let diskBudget: Int64 = 50 * 1024 * 1024
    static let vacuumInterval: Int64 = 7 * 86400
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "history")

    /// Returns true when maintenance ran. `fileSize` overrides the measured size (tests).
    @discardableResult
    public func runMaintenanceIfDue(
        now: Date,
        calendar: Calendar,
        rawDays: Int,
        fileSize: (() -> Int64)? = nil
    ) async throws -> Bool {
        let today = calendar.startOfDay(for: now)
        let dayKey = Int64(today.timeIntervalSince1970)
        let last = try await meta("maint_day").flatMap(Int64.init)
        if let last {
            guard dayKey > last else { return false }
            let three = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? today
            guard now >= three else { return false }
        }
        let size = fileSize ?? { self.fileSizeBytes() }
        var days = rawDays
        if size() > Self.shrinkThreshold {
            days = min(days, 30)
            Self.log.notice("history file over 100 MB; raw window shrunk to 30 days")
        }
        let nowS = Int64(now.timeIntervalSince1970)
        try await rollup(cutoff: nowS - Int64(days) * 86400, hourlyCutoff: nowS - Int64(Self.hourlyRetention))
        let lastVac = try await meta("vacuum_ts").flatMap(Int64.init) ?? 0
        if nowS - lastVac >= Self.vacuumInterval { try await vacuum(now: nowS) }
        try await enforceBudget(size: size, now: nowS)
        try await setMeta("maint_day", "\(dayKey)")
        return true
    }

    /// Raw rows older than `cutoff` fold into hourly rows and are deleted in the same transaction.
    func rollup(cutoff: Int64, hourlyCutoff: Int64) async throws {
        try await db.write { db in
            try db.execute(sql: """
                INSERT INTO sample_hourly (account_id, meter, hour, percent_max, percent_last, resets_at_last)
                SELECT account_id, meter, h, pmax,
                  (SELECT percent FROM sample s2 WHERE s2.account_id = g.account_id AND s2.meter = g.meter AND s2.ts = g.tlast),
                  (SELECT resets_at FROM sample s2 WHERE s2.account_id = g.account_id AND s2.meter = g.meter AND s2.ts = g.tlast)
                FROM (SELECT account_id, meter, (ts / 3600) * 3600 AS h, MAX(percent) AS pmax, MAX(ts) AS tlast
                      FROM sample WHERE ts < :cut GROUP BY account_id, meter, h) g
                WHERE true
                ON CONFLICT (account_id, meter, hour) DO UPDATE SET
                  percent_max = CASE WHEN percent_max IS NULL OR excluded.percent_max > percent_max
                                     THEN excluded.percent_max ELSE percent_max END,
                  percent_last = excluded.percent_last,
                  resets_at_last = excluded.resets_at_last
                """, arguments: ["cut": cutoff])
            try db.execute(sql: "DELETE FROM sample WHERE ts < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM sample_hourly WHERE hour < ?", arguments: [hourlyCutoff])
            try db.execute(sql: "DELETE FROM spend_sample WHERE ts < ?", arguments: [hourlyCutoff])
        }
    }

    func vacuum(now: Int64) async throws {
        try await db.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA incremental_vacuum")
            if db.configuration.readonly == false, (try? String.fetchOne(db, sql: "PRAGMA journal_mode")) == "wal" {
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
        }
        try await setMeta("vacuum_ts", "\(now)")
    }

    /// Over budget: drop the oldest hourly day at a time, vacuuming, until under or none left.
    func enforceBudget(size: () -> Int64, now: Int64) async throws {
        while size() > Self.diskBudget {
            let oldest = try await db.read { try Int64.fetchOne($0, sql: "SELECT MIN(hour) FROM sample_hourly") }
            guard let oldest else { return }
            try await db.write { try $0.execute(sql: "DELETE FROM sample_hourly WHERE hour < ?", arguments: [oldest + 86400]) }
            try await vacuum(now: now)
            Self.log.notice("history over 50 MB budget; dropped oldest hourly day")
        }
    }

    func meta(_ key: String) async throws -> String? {
        try await db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }

    func setMeta(_ key: String, _ value: String) async throws {
        try await db.write { try $0.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, value]) }
    }
}
