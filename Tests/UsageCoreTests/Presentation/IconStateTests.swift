import Foundation
import Testing
@testable import UsageCore

@Suite struct IconStateTests {
    let now = Date(timeIntervalSince1970: 1_800_023_520)
    let a = AccountID(kind: .claude, remoteID: "a")
    let b = AccountID(kind: .copilot, remoteID: "b")

    func claude(_ p: Double, resetsIn: TimeInterval = 3 * 3600) -> UsageSnapshot {
        UsageSnapshot(accountID: a, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .session5h, label: "Session usage", percentUsed: p,
                  resetsAt: now.addingTimeInterval(resetsIn), windowLength: .seconds(5 * 3600)),
        ], spend: nil)
    }
    func copilot(_ p: Double) -> UsageSnapshot {
        UsageSnapshot(accountID: b, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: p, used: p, limit: 100),
        ], spend: nil)
    }
    func make(_ snaps: [AccountID: UsageSnapshot], _ statuses: [AccountID: AccountStatus] = [:],
              menuBar: AccountID? = nil, order: [AccountID]? = nil) -> IconState {
        IconState.make(appState: snaps, statuses: statuses, menuBarAccount: menuBar,
                       order: order ?? [a, b].filter { snaps[$0] != nil }, now: now)
    }

    @Test func noAccountsEmpty() {
        #expect(make([:]) == .empty)
    }

    @Test func thresholds() {
        #expect(make([a: claude(74)]).level == .normal)
        #expect(make([a: claude(75)]).level == .warning)
        #expect(make([a: claude(89.6)]).level == .critical) // rounds to 90
        #expect(make([a: claude(90)]) == IconState(level: .critical, percent: 90, pace: 40, caption: "5H"))
    }

    @Test func paceFromWindow() {
        #expect(make([a: claude(10, resetsIn: 3 * 3600)]).pace == 40)
    }

    @Test func staleOutline() {
        let s = make([a: claude(42)], [a: .stale])
        #expect(s.level == .outline)
        #expect(s.percent == 42)
    }

    @Test func needsLoginOutline() {
        #expect(make([a: claude(42)], [a: .needsLogin]).level == .outline)
    }

    @Test func menuBarAccountMissingFallsBack() {
        let gone = AccountID(kind: .claude, remoteID: "gone")
        let s = make([b: copilot(33)], menuBar: gone, order: [b])
        #expect(s.percent == 33)
        #expect(s.caption == "PR")
    }

    @Test func menuBarAccountPicked() {
        #expect(make([a: claude(10), b: copilot(80)], menuBar: b).percent == 80)
    }

    @Test func equalStateNoRedraw() {
        #expect(make([a: claude(42.2)]) == make([a: claude(41.8)]))
        #expect(make([a: claude(42)]) != make([a: claude(43)]))
    }
}
