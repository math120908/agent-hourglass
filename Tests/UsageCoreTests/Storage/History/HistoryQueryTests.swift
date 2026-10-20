import Foundation
import GRDB
import Testing
@testable import UsageCore

@Suite struct HistoryQueryTests {
    let acct = AccountID(rawValue: "claude:A")!
    let t0: TimeInterval = 1_800_000_000
    var now: Date { Date(timeIntervalSince1970: t0 + 86400) }
    var day: DateInterval { DateInterval(start: Date(timeIntervalSince1970: t0), duration: 86400) }

    private func seed(_ rows: [(String, Double, Double?, Double?)]) async throws -> HistoryQuery {
        let s = try HistoryStore.inMemory()
        try await s.db.write { db in
            for (m, ts, p, r) in rows {
                try db.execute(
                    sql: "INSERT INTO sample (account_id, meter, ts, percent, resets_at) VALUES (?, ?, ?, ?, ?)",
                    arguments: [acct.rawValue, m, Int64(ts), p, r.map { Int64($0) }])
            }
        }
        let n = now
        return HistoryQuery(store: s, now: { n })
    }

    @Test func splitsOnReset() async throws {
        let q = try await seed([
            ("session5h", t0 + 60, 10, t0 + 18000), ("session5h", t0 + 1800, 50, t0 + 18000),
            ("session5h", t0 + 3600, 0, t0 + 36000), ("session5h", t0 + 5400, 5, t0 + 36000),
        ])
        let s = try await q.series(account: acct, range: day)
        #expect(s.map(\.id) == ["session5h@\(Int64(t0 + 18000))", "session5h@\(Int64(t0 + 36000))"])
        #expect(s.map { $0.points.compactMap(\.percent) } == [[10, 50], [0, 5]])
    }

    @Test func carriesForwardToRangeStart() async throws {
        let q = try await seed([("weeklyAll", t0 - 600, 42, nil), ("weeklyAll", t0 + 600, 43, nil)])
        let s = try await q.series(account: acct, range: day)
        #expect(s[0].points.first == SeriesPoint(t: day.start, percent: 42))
    }

    @Test func gapInserted() async throws {
        let q = try await seed([("weeklyAll", t0, 1, nil), ("weeklyAll", t0 + 4 * 3600, 2, nil)])
        let p = try await q.series(account: acct, range: day)[0].points
        #expect(p.map(\.percent) == [1, nil, 2])
    }

    @Test func downsampleMax500KeepsPeaks() async throws {
        var rows: [(String, Double, Double?, Double?)] = []
        for i in 0..<1440 { rows.append(("session5h", t0 + Double(i * 60), i == 777 ? 99 : Double(i % 30), 1)) }
        let q = try await seed(rows)
        let p = try await q.series(account: acct, range: day)[0].points
        #expect(p.count <= 500)
        #expect(p.contains { $0.percent == 99 })
        #expect(p.first?.t == day.start)
        #expect(p.last?.t == Date(timeIntervalSince1970: t0 + 1439 * 60))
    }

    @Test func hourlyBeyondRawWindow() async throws {
        let q = try await seed([])
        let old = t0 - 100 * 86400
        try await q.store.db.write { db in
            try db.execute(sql: "INSERT INTO sample_hourly VALUES (?, 'session5h', ?, 95, 30, 7)", arguments: [acct.rawValue, Int64(old)])
            // A raw row older than the window is ignored (rollup owns that period).
            try db.execute(sql: "INSERT INTO sample (account_id, meter, ts, percent) VALUES (?, 'session5h', ?, 12)", arguments: [acct.rawValue, Int64(old + 60)])
        }
        let r = DateInterval(start: Date(timeIntervalSince1970: old - 3600), duration: 7200)
        #expect(try await q.series(account: acct, range: r)[0].points.map(\.percent) == [30])
        let sum = try await q.summary(account: acct, range: r)
        #expect(sum.peakSession == 95 && sum.windowsOver90 == 1)
    }

    @Test func summaryValues() async throws {
        let q = try await seed([
            ("session5h", t0 + 60, 91, 1), ("session5h", t0 + 120, 40, 2),
            ("session5h", t0 + 180, 97, 3), ("session5h", t0 + 240, 89, 4),
            ("weeklyAll", t0 + 60, 20, nil), ("weeklyAll", t0 + 7200, 33, nil),
            ("weeklyAll", t0 + 90000, 50, nil),
        ])
        let s = try await q.summary(account: acct, range: day)
        #expect(s == RangeSummary(peakSession: 97, windowsOver90: 2, weeklyAtEnd: 33))
    }

    @Test func emptyRange() async throws {
        let q = try await seed([("session5h", t0 + 200_000, 50, 1)])
        #expect(try await q.series(account: acct, range: day).isEmpty)
        #expect(try await q.summary(account: acct, range: day) == RangeSummary(peakSession: nil, windowsOver90: 0, weeklyAtEnd: nil))
    }
}
