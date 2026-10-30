import Foundation
import Testing
@testable import UsageCore

@Suite struct ModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func meter(percent: Double?, resetsIn: TimeInterval?, window: Duration?) -> Meter {
        Meter(
            kind: .session5h,
            label: "Session",
            percentUsed: percent,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            windowLength: window
        )
    }

    @Test func paceMidWindow() {
        let m = meter(percent: 10, resetsIn: 2.5 * 3600, window: .seconds(5 * 3600))
        #expect(m.paceFraction(now: now) == 0.5)
        #expect(meter(percent: 10, resetsIn: nil, window: .seconds(3600)).paceFraction(now: now) == nil)
        #expect(meter(percent: 10, resetsIn: 3600, window: nil).paceFraction(now: now) == nil)
        #expect(meter(percent: 10, resetsIn: 99_999, window: .seconds(3600)).paceFraction(now: now) == 0)
        #expect(meter(percent: 10, resetsIn: -10, window: .seconds(3600)).paceFraction(now: now) == 1)
    }

    @Test func aheadOfPace() {
        #expect(meter(percent: 60, resetsIn: 2.5 * 3600, window: .seconds(5 * 3600)).isAheadOfPace(now: now))
        #expect(!meter(percent: 40, resetsIn: 2.5 * 3600, window: .seconds(5 * 3600)).isAheadOfPace(now: now))
        #expect(!meter(percent: 60, resetsIn: nil, window: nil).isAheadOfPace(now: now))
    }

    @Test func severityThresholds() {
        #expect(meter(percent: 74, resetsIn: nil, window: nil).displaySeverity(now: now) == .normal)
        #expect(meter(percent: 75, resetsIn: nil, window: nil).displaySeverity(now: now) == .warning)
        #expect(meter(percent: 90, resetsIn: nil, window: nil).displaySeverity(now: now) == .critical)
        var p = meter(percent: 10, resetsIn: nil, window: nil)
        p.severity = .warning
        #expect(p.displaySeverity(now: now) == .warning)
    }

    @Test func accountIDRoundTrip() throws {
        let id = AccountID(kind: .claude, remoteID: "abc")
        #expect(id.rawValue == "claude:abc")
        #expect(id.kind == .claude)
        #expect(AccountID(rawValue: "bogus:x")?.kind == nil)
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"claude:abc\"")
        #expect(try JSONDecoder().decode(AccountID.self, from: data) == id)
    }

    @Test func snapshotCodableRoundTrip() throws {
        let snap = UsageSnapshot(
            accountID: AccountID(kind: .claude, remoteID: "abc"),
            fetchedAt: now,
            plan: "max_20x",
            meters: [meter(percent: 42, resetsIn: 3600, window: .seconds(5 * 3600))],
            spend: Money(usedMinor: 85, limitMinor: 2000, currency: "EUR", exponent: 2),
            rawUnknownKeys: ["foo"]
        )
        let data = try JSONEncoder().encode(snap)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == snap)
        let status = AccountStatus.rateLimited(retryAt: now)
        #expect(try JSONDecoder().decode(AccountStatus.self, from: JSONEncoder().encode(status)) == status)
    }

    @Test func usesWindowMeters() {
        #expect(ProviderKind.codex.usesWindowMeters)
        #expect(!ProviderKind.claude.usesWindowMeters)
        #expect(!ProviderKind.copilot.usesWindowMeters)
    }
}
