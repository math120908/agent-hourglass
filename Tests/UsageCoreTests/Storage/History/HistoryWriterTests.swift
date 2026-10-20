import Foundation
import GRDB
import Testing
@testable import UsageCore

@Suite struct HistoryWriterTests {
    let acct = AccountID(rawValue: "a1")!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(_ t: Date, _ pct: Double, meters: [Meter]? = nil, spend: Money? = nil) -> UsageSnapshot {
        UsageSnapshot(accountID: acct, fetchedAt: t, meters: meters ?? [Meter(kind: .session5h, label: "Session", percentUsed: pct)], spend: spend)
    }

    func count(_ s: HistoryStore, _ table: String = "sample") throws -> Int {
        try s.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    @Test func unchangedSkipped() async throws {
        let s = try HistoryStore.inMemory()
        try await s.record(snap(t0, 10))
        try await s.record(snap(t0.addingTimeInterval(300), 10))
        #expect(try count(s) == 1)
    }

    @Test func changeWritten() async throws {
        let s = try HistoryStore.inMemory()
        try await s.record(snap(t0, 10))
        try await s.record(snap(t0.addingTimeInterval(300), 11))
        #expect(try count(s) == 2)
    }

    @Test func heartbeatAfter60Min() async throws {
        let s = try HistoryStore.inMemory()
        try await s.record(snap(t0, 10))
        try await s.record(snap(t0.addingTimeInterval(3599), 10))
        try await s.record(snap(t0.addingTimeInterval(3600), 10))
        #expect(try count(s) == 2)
    }

    @Test func weeklyModelKeyed() async throws {
        let s = try HistoryStore.inMemory()
        try await s.record(snap(t0, 0, meters: [Meter(kind: .weeklyModel, label: "Fable", percentUsed: 5)]))
        let m = try await s.db.read { try String.fetchOne($0, sql: "SELECT meter FROM sample") }
        #expect(m == "weeklyModel:Fable")
    }

    @Test func spendWrittenSeparately() async throws {
        let s = try HistoryStore.inMemory()
        let money = Money(usedMinor: 85, limitMinor: 2000, currency: "EUR", exponent: 2)
        try await s.record(snap(t0, 10, spend: money))
        try await s.record(snap(t0.addingTimeInterval(60), 11, spend: money))
        #expect(try count(s) == 2)
        #expect(try count(s, "spend_sample") == 1)
    }

    @Test func duplicateTsIgnored() async throws {
        let s = try HistoryStore.inMemory()
        try await s.record(snap(t0, 10))
        try await s.record(snap(t0.addingTimeInterval(-60), 20))
        try await s.record(snap(t0, 30))  // clock jumped back: same PK
        #expect(try count(s) == 2)
    }

    @Test func seededFromDBOnOpen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hw-\(UUID().uuidString).sqlite")
        try await HistoryStore(url: url).record(snap(t0, 10))
        let reopened = try HistoryStore(url: url)
        try await reopened.record(snap(t0.addingTimeInterval(60), 10))
        #expect(try count(reopened) == 1)
    }
}
