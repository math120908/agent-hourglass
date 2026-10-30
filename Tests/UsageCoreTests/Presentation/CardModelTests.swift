import Foundation
import Testing
@testable import UsageCore

@Suite struct CardModelTests {
    // 2027-01-15 14:32:00 UTC (Friday)
    let now = Date(timeIntervalSince1970: 1_800_023_520)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let locale = Locale(identifier: "en_US_POSIX")
    let claudeID = AccountID(kind: .claude, remoteID: "a")
    let copilotID = AccountID(kind: .copilot, remoteID: "b")

    func session(_ p: Double?, resetsIn: TimeInterval?) -> Meter {
        Meter(kind: .session5h, label: "Session usage", percentUsed: p,
              resetsAt: resetsIn.map { now.addingTimeInterval($0) }, windowLength: .seconds(5 * 3600))
    }
    func weekly(_ p: Double, resetsIn: TimeInterval) -> Meter {
        Meter(kind: .weeklyAll, label: "All models, weekly", percentUsed: p,
              resetsAt: now.addingTimeInterval(resetsIn), windowLength: .seconds(7 * 86400))
    }
    func claude(_ meters: [Meter], spend: Money? = nil, plan: String? = "max_20x", age: TimeInterval = 30) -> UsageSnapshot {
        UsageSnapshot(accountID: claudeID, fetchedAt: now.addingTimeInterval(-age), plan: plan, meters: meters, spend: spend)
    }
    func make(_ s: UsageSnapshot?, _ status: AccountStatus = .fresh, _ kind: ProviderKind = .claude) -> CardModel {
        CardModel.make(snapshot: s, status: status, kind: kind, now: now, calendar: cal, locale: locale)
    }
    func premium(used: Double, limit: Double, unlimited: Bool = false) -> Meter {
        Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: limit > 0 ? used / limit * 100 : nil,
              used: used, limit: limit, unit: "credits", resetsAt: Date(timeIntervalSince1970: 1_801_440_000),
              isUnlimited: unlimited)
    }

    @Test func notStarted() {
        #expect(make(claude([session(nil, resetsIn: nil)])).headline?.resetText == "Not started")
    }
    @Test func resetsInWithClock() {
        let m = make(claude([session(42, resetsIn: 98 * 60)]))
        #expect(m.headline?.resetText == "Resets in 1 h 38 min (16:10)")
        #expect(m.headline?.percentText == "42%")
        #expect(m.headline?.severity == .normal)
    }
    @Test func resetInPastShowsResetting() {
        #expect(make(claude([session(80, resetsIn: -120)])).headline?.resetText == "Resetting…")
    }
    @Test func onPace() {
        // half the week elapsed, 50% used
        let row = make(claude([weekly(50, resetsIn: 3.5 * 86400)])).rows.first
        #expect(row?.paceText == "On pace")
        #expect(row?.paceTick == 0.5)
    }
    @Test func aheadOfPace() {
        let row = make(claude([weekly(58, resetsIn: 3.5 * 86400)])).rows.first
        #expect(row?.paceText == "8% ahead of pace")
        #expect(row?.severity == .warning)
    }
    @Test func underPace() {
        #expect(make(claude([weekly(37, resetsIn: 3.5 * 86400)])).rows.first?.paceText == "13% under pace")
    }
    @Test func severityColors() {
        #expect(make(claude([session(76, resetsIn: 4.9 * 3600)])).headline?.severity == .warning)
        #expect(make(claude([session(91, resetsIn: 4.9 * 3600)])).headline?.severity == .critical)
    }
    @Test func secondaryWeekly() {
        #expect(make(claude([session(42, resetsIn: 3600), weekly(39, resetsIn: 86400)])).secondary == "Wk 39%")
    }
    @Test func updatedAgo() {
        #expect(make(claude([session(1, resetsIn: 3600)], age: 23 * 60), .stale).updatedText == "Updated 23 min ago")
        #expect(make(claude([session(1, resetsIn: 3600)], age: 2 * 3600)).updatedText == "Updated 12:32")
    }
    @Test func rateLimited() {
        let m = make(claude([session(1, resetsIn: 3600)]), .rateLimited(retryAt: now))
        #expect(m.statusChip == "Rate limited, retry 14:32")
        #expect(m.isDimmed)
    }
    @Test func schemaError() {
        #expect(make(claude([session(1, resetsIn: 3600)]), .schemaError).statusChip == "Response format changed")
    }
    @Test func staleNeedsLoginOfflineChips() {
        let s = claude([session(1, resetsIn: 3600)])
        #expect(make(s, .stale).statusChip == "Stale")
        #expect(make(s, .offline).statusChip == nil)
        #expect(make(s, .offline).isDimmed)
        #expect(make(s, .needsLogin).statusChip == "Sign in again")
        #expect(make(s, .quotaUnavailable).statusChip == "Quota unavailable")
        #expect(make(s, .fresh).statusChip == nil)
        #expect(!make(s, .fresh).isDimmed)
    }
    @Test func copilotGhChips() {
        let cp: (AccountStatus, String?) -> String? = { st, login in
            CardModel.make(snapshot: nil, status: st, kind: .copilot, now: self.now, calendar: self.cal, locale: self.locale, login: login).statusChip
        }
        #expect(cp(.needsLogin, nil) == "Run `gh auth login`")
        #expect(cp(.ghMissing, nil) == "Install gh (Homebrew)")
        #expect(cp(.ghLoginRemoved, "pikachu-dev") == "Login `pikachu-dev` not in gh; run `gh auth login`")
    }
    @Test func spendEnabled() {
        let m = make(claude([], spend: Money(usedMinor: 85, limitMinor: 2000, currency: "EUR", exponent: 2)))
        #expect(m.spend == SpendRow(text: "0.85 / 20.00 EUR", fraction: 0.0425, chip: nil))
    }
    @Test func spendDisabled() {
        let money = Money(usedMinor: 2000, limitMinor: 2000, currency: "EUR", exponent: 2,
                          isEnabled: false, disabledReason: "out_of_credits")
        let sp = make(claude([], spend: money)).spend
        #expect(sp?.fraction == 1)
        #expect(sp?.chip == "Disabled: out of credits")
    }
    @Test func planTags() {
        #expect(make(claude([], plan: "max_20x")).planTag == "Max 20x")
        #expect(make(claude([], plan: "pro")).planTag == "Pro")
        #expect(make(claude([], plan: "enterprise")).planTag == "Enterprise")
        #expect(make(claude([], plan: "free")).planTag == "Free")
    }
    @Test func copilotCredits() {
        let s = UsageSnapshot(accountID: copilotID, fetchedAt: now, plan: "enterprise",
                              meters: [premium(used: 62_500, limit: 250_000)])
        let h = make(s, .fresh, .copilot).headline
        #expect(h?.percentText == "25%")
        #expect(h?.detailText == "62,500 / 250,000 credits (≈ $625 / $2,500)")
        #expect(h?.resetText == "Resets Feb 1")
    }
    @Test func copilotZeroEntitlement() {
        let s = UsageSnapshot(accountID: copilotID, fetchedAt: now, meters: [premium(used: 0, limit: 0)])
        let h = make(s, .fresh, .copilot).headline
        #expect(h?.percentText == "Not included")
        #expect(h?.fraction == nil)
    }
    @Test func unlimitedHidden() {
        let chat = Meter(kind: .copilotChat, label: "Chat", percentUsed: nil, isUnlimited: true)
        let s = UsageSnapshot(accountID: copilotID, fetchedAt: now, meters: [premium(used: 10, limit: 300), chat])
        #expect(make(s, .fresh, .copilot).rows.map(\.label) == ["Premium requests"])
    }
    @Test func staleDimmedKeepsValues() {
        let m = make(claude([session(42, resetsIn: 3600)], age: 23 * 60), .stale)
        #expect(m.isDimmed)
        #expect(m.headline?.percentText == "42%")
    }
    @Test func noDataSkeleton() {
        let m = make(nil, .noData)
        #expect(m.headline == nil && m.rows.isEmpty && m.spend == nil)
        #expect(m.updatedText == "No data yet")
        #expect(!m.isDimmed)
    }
    @Test func neverMiddleDot() {
        let m = make(claude([session(42, resetsIn: 3600), weekly(39, resetsIn: 86400)],
                            spend: Money(usedMinor: 1, limitMinor: 2, currency: "EUR", exponent: 2)), .stale)
        #expect(!String(describing: m).contains("\u{00B7}"))
    }

    func window(_ seconds: Int, _ p: Double) -> Meter {
        Meter(kind: .window, label: Meter.windowLabel(seconds: seconds), percentUsed: p,
              resetsAt: now.addingTimeInterval(3600), windowLength: .seconds(seconds))
    }
    func codex(_ meters: [Meter]) -> UsageSnapshot {
        UsageSnapshot(accountID: AccountID(kind: .codex, remoteID: "c"), fetchedAt: now, plan: nil, meters: meters, spend: nil)
    }
    @Test func codexHeadlineAndSecondary() {
        let m = make(codex([window(18000, 12), window(604_800, 50)]), .fresh, .codex)
        #expect(m.headline?.label == Meter.windowLabel(seconds: 18000))
        #expect(m.secondary == "Wk 50%")
    }
    @Test func secondarySkipsSameLengthWindow() {
        #expect(make(codex([window(604_800, 96), window(604_800, 84)]), .fresh, .codex).secondary == nil)
        #expect(make(codex([window(18000, 10), window(18000, 20), window(604_800, 50)]), .fresh, .codex).secondary == "Wk 50%")
    }
    @Test func grokHeadlineIsWeeklyWindow() {
        var build = window(604_800, 84)
        build.label = "Build"
        build.pool = "build"
        var chat = window(604_800, 12)
        chat.label = "Chat"
        chat.pool = "chat"
        let snap = UsageSnapshot(accountID: AccountID(kind: .grok, remoteID: "g"), fetchedAt: now, plan: nil,
                                 meters: [window(604_800, 96), build, chat], spend: nil)
        let m = make(snap, .fresh, .grok)
        #expect(m.headline?.label == Meter.windowLabel(seconds: 604_800))
        #expect(m.headline?.percentText == "96%")
        #expect(m.secondary == nil)
    }
}
