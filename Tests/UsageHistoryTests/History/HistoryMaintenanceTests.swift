import Foundation
import GRDB
import Testing
@testable import UsageCore
@testable import UsageHistory

@Suite struct HistoryMaintenanceTests {
    let t0: Int64 = 1_800_000_000 / 3600 * 3600

    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func insert(_ s: HistoryStore, _ ts: Int64, _ pct: Double, resets: Int64? = nil, acct: String = "a", meter: String = "session5h") throws {
        try s.db.write {
            try $0.execute(sql: "INSERT INTO sample (account_id, meter, ts, percent, resets_at) VALUES (?, ?, ?, ?, ?)", arguments: [acct, meter, ts, pct, resets])
        }
    }

    func count(_ s: HistoryStore, _ table: String) throws -> Int {
        try s.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    @Test func rollupCorrect() async throws {
        let s = try HistoryStore.inMemory()
        try insert(s, t0 + 10, 30, resets: 1)
        try insert(s, t0 + 20, 80, resets: 1)
        try insert(s, t0 + 30, 50, resets: 2)
        try insert(s, t0 + 3700, 5)
        try await s.rollup(cutoff: t0 + 3600, hourlyCutoff: 0)
        let r: (Int64, Double, Double, Int64)? = try await s.db.read { db in
            try Row.fetchOne(db, sql: "SELECT hour, percent_max, percent_last, resets_at_last FROM sample_hourly").map { ($0[0], $0[1], $0[2], $0[3]) }
        }
        #expect(r?.0 == t0)
        #expect(r?.1 == 80.0)
        #expect(r?.2 == 50.0)
        #expect(r?.3 == 2)
        #expect(try count(s, "sample_hourly") == 1)
    }

    @Test func rawOlderThanWindowDeleted() async throws {
        let s = try HistoryStore.inMemory()
        let now = t0 + 100 * 86400
        try insert(s, now - 91 * 86400, 10)
        try insert(s, now - 89 * 86400, 20)
        try await s.runMaintenanceIfDue(now: Date(timeIntervalSince1970: TimeInterval(now)), calendar: utc, rawDays: 90)
        #expect(try count(s, "sample") == 1)
        #expect(try count(s, "sample_hourly") == 1)
    }

    @Test func hourlyOlderThan2yDeleted() async throws {
        let s = try HistoryStore.inMemory()
        let now = t0 + 800 * 86400
        try await s.db.write {
            try $0.execute(sql: "INSERT INTO sample_hourly (account_id, meter, hour, percent_max) VALUES ('a','m',?,1), ('a','m',?,2)",
                           arguments: [now - 731 * 86400, now - 700 * 86400])
        }
        try await s.runMaintenanceIfDue(now: Date(timeIntervalSince1970: TimeInterval(now)), calendar: utc, rawDays: 90)
        #expect(try count(s, "sample_hourly") == 1)
    }

    @Test func maintenanceOncePerDayAcrossDST() async throws {
        let s = try HistoryStore.inMemory()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        // 2026-03-29: clocks jump 01:00 -> 02:00 in Dublin; 2026-10-25: 02:00 -> 01:00.
        for day in ["2026-03-29", "2026-10-25"] {
            let f = ISO8601DateFormatter()
            let midnight = f.date(from: day + "T00:00:00Z")!
            var ran = 0
            // Day before seeds last run.
            try await s.setMeta("maint_day", "\(Int64(cal.startOfDay(for: midnight.addingTimeInterval(-86400)).timeIntervalSince1970))")
            for minute in stride(from: 0, to: 26 * 60, by: 10) {
                if try await s.runMaintenanceIfDue(now: midnight.addingTimeInterval(TimeInterval(minute * 60)), calendar: cal, rawDays: 90) { ran += 1 }
            }
            #expect(ran == 1, "\(day)")
        }
    }

    @Test func runsOnFirstLaunchBefore3am() async throws {
        let s = try HistoryStore.inMemory()
        let early = Date(timeIntervalSince1970: TimeInterval(t0 - t0 % 86400 + 3600))
        #expect(try await s.runMaintenanceIfDue(now: early, calendar: utc, rawDays: 90))
        #expect(try await !s.runMaintenanceIfDue(now: early.addingTimeInterval(7200), calendar: utc, rawDays: 90))
    }

    @Test func over100MBDropsTo30Days() async throws {
        let s = try HistoryStore.inMemory()
        let now = t0 + 100 * 86400
        try insert(s, now - 31 * 86400, 10)
        try insert(s, now - 29 * 86400, 20)
        try await s.runMaintenanceIfDue(now: Date(timeIntervalSince1970: TimeInterval(now)), calendar: utc, rawDays: 90, fileSize: { 101 * 1024 * 1024 })
        #expect(try count(s, "sample") == 1)
    }

    @Test func overBudgetDropsOldestHourlyFirst() async throws {
        let s = try HistoryStore.inMemory()
        let now = t0 + 400 * 86400
        try await s.db.write {
            try $0.execute(sql: "INSERT INTO sample_hourly (account_id, meter, hour) VALUES ('a','m',?), ('a','m',?)",
                           arguments: [now - 300 * 86400, now - 200 * 86400])
        }
        try insert(s, now - 86400, 1)
        var calls = 0
        // Over budget until one hourly day has been dropped.
        try await s.runMaintenanceIfDue(now: Date(timeIntervalSince1970: TimeInterval(now)), calendar: utc, rawDays: 90, fileSize: {
            calls += 1
            return calls <= 2 ? 60 * 1024 * 1024 : 1
        })
        let hours = try await s.db.read { try Int64.fetchAll($0, sql: "SELECT hour FROM sample_hourly") }
        #expect(hours == [now - 200 * 86400])
        #expect(try count(s, "sample") == 1)
    }

    /// Guards against runaway growth (cf. competitor CUT #337, 10–17 GB/h): 6 accounts, 1-min tick,
    /// 1-in-5 change rate during 12 active hours, 120 simulated days with daily maintenance, on disk.
    @Test func soak120Days6Accounts() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
        var rng = SystemRandomNumberGenerator.Seeded(seed: 42)
        let accounts = (0..<6).map { AccountID(rawValue: "claude:acct\($0)")! }
        var pct = [Double](repeating: 0, count: 6)
        let start = t0 - t0 % 86400
        let days = 120
        for minute in 0..<(days * 1440) {
            let t = start + Int64(minute) * 60
            let active = (minute % 1440) >= 8 * 60 && (minute % 1440) < 20 * 60
            if minute % 1440 == 3 * 60 + 1 {
                try await s.runMaintenanceIfDue(now: Date(timeIntervalSince1970: TimeInterval(t)), calendar: utc, rawDays: 90)
            }
            for (i, a) in accounts.enumerated() {
                let changed = active && rng.next() % 5 == 0
                // Unchanged ticks are no-ops in the writer except at the heartbeat; skip them to keep runtime low.
                guard changed || minute % 60 == 0 else { continue }
                if changed { pct[i] = (pct[i] + 1).truncatingRemainder(dividingBy: 100) }
                let resets = Date(timeIntervalSince1970: TimeInterval(t - t % 18000 + 18000))
                try await s.record(UsageSnapshot(accountID: a, fetchedAt: Date(timeIntervalSince1970: TimeInterval(t)), meters: [
                    Meter(kind: .session5h, label: "Session", percentUsed: pct[i], resetsAt: resets),
                    Meter(kind: .weeklyAll, label: "Weekly", percentUsed: pct[i] / 2),
                    Meter(kind: .weeklyModel, label: "Fable", percentUsed: pct[i] / 3),
                ]))
            }
        }
        try await s.vacuum(now: start + Int64(days) * 86400)
        let size = s.fileSizeBytes()
        print("soak: \(days) days, 6 accounts -> \(size) bytes (\(String(format: "%.2f", Double(size) / 1_048_576)) MB)")
        #expect(try count(s, "sample_hourly") > 0)
        // 90 raw days of 3 meters x 6 accounts is the steady-state peak; must sit well under the 50 MB budget.
        #expect(size < HistoryStore.diskBudget / 2)
    }
}

extension SystemRandomNumberGenerator {
    /// Deterministic xorshift for reproducible soak runs.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }
}
