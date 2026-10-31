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

    @Test func claudeWithoutSessionShowsWeekly() {
        let snap = UsageSnapshot(accountID: a, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .weeklyAll, label: "All models", percentUsed: 6,
                  resetsAt: now.addingTimeInterval(6 * 86400), windowLength: .seconds(7 * 86400)),
        ], spend: nil)
        let s = make([a: snap])
        #expect(s.caption == "WK")
        #expect(s.percent == 6)
        #expect(s.level == .normal)
        #expect(s.weekly == nil)
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

    @Test func secondSkipsSameLengthWindow() {
        let c = AccountID(kind: .codex, remoteID: "c")
        func window(_ seconds: Int, _ p: Double) -> Meter {
            Meter(kind: .window, label: Meter.windowLabel(seconds: seconds), percentUsed: p,
                  resetsAt: now.addingTimeInterval(3600), windowLength: .seconds(seconds))
        }
        func snap(_ meters: [Meter]) -> [AccountID: UsageSnapshot] {
            [c: UsageSnapshot(accountID: c, fetchedAt: now, plan: nil, meters: meters, spend: nil)]
        }
        let same = IconState.make(appState: snap([window(604_800, 96), window(604_800, 84)]), statuses: [:], menuBarAccount: nil, order: [c], now: now)
        #expect(same.weekly == nil)
        let mixed = IconState.make(appState: snap([window(18000, 10), window(18000, 20), window(604_800, 50)]), statuses: [:], menuBarAccount: nil, order: [c], now: now)
        #expect(mixed.weekly == 50)
    }
}
