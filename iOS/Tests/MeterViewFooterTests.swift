import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct MeterViewFooterTests {
    private let now = Date(timeIntervalSince1970: 1_792_853_160)  // 2026-10-24 14:46 UTC

    private func display(_ m: Meter, remaining: Bool = false) -> MeterDisplay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = DisplaySettings(showRemaining: remaining, resetStyle: .clock, hour24: .on, refreshMinutes: 1)
        return MeterDisplay.make(m, now: now, options: s.meterOptions(calendar: cal, locale: Locale(identifier: "en_US")))
    }

    private var reset: Date { now.addingTimeInterval(37 * 86_400) }  // Nov 30

    private var credits: Meter {
        Meter(
            kind: .window,
            label: "Credits",
            percentUsed: 0.2,
            used: 200,
            limit: 130_539,
            unit: "credits",
            resetsAt: reset,
            windowLength: .seconds(60 * 86_400)
        )
    }

    private var premium: Meter {
        Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: 33.7, used: 84_250, limit: 250_000, unit: "credits", resetsAt: reset)
    }

    @Test func testCreditsShowUsageAndKeepReset() {
        let d = display(credits)
        #expect(MeterView.percent(d) == "0.2%")
        let glass = MeterView.footerLines(d, theme: .glass)
        #expect(glass == [.init(left: "200 / 130,539 credits", right: "Resets Nov 30", resetSide: .right)])
        let inst = MeterView.footerLines(d, theme: .instrument)
        #expect(inst.first == .init(left: "200 / 130,539 credits", right: "Resets Nov 30", resetSide: .right))
        #expect(inst.count == 2 && inst[1].left.isEmpty && inst[1].right == d.paceText)
    }

    @Test func testCopilotPremiumSplitsMoneyLine() {
        let d = display(premium)
        #expect(MeterView.percent(d) == "33.7%")
        #expect(MeterView.footerLines(d, theme: .glass) == [
            .init(left: "84,250 / 250,000 credits", right: "Resets Nov 30", resetSide: .right),
            .init(left: "≈ $843 / $2,500", right: "66.3% remaining"),
        ])
        #expect(MeterView.footerLines(d, theme: .instrument) == [
            .init(left: "84,250 / 250,000 credits", right: "Resets Nov 30", resetSide: .right),
            .init(left: "≈ $843 / $2,500", right: ""),
        ])
        let r = display(premium, remaining: true)
        #expect(MeterView.percent(r) == "66.3%")
        #expect(MeterView.footerLines(r, theme: .glass)[1].right == "33.7% used")
    }

    @Test func testMetersWithoutDetailUnchanged() {
        let m = Meter(kind: .window, label: "30-day", percentUsed: 0, resetsAt: reset, windowLength: .seconds(30 * 86_400))
        let d = display(m)
        #expect(MeterView.percent(d) == d.percentText)
        #expect(MeterView.footerLines(d, theme: .glass) == [.init(left: d.resetText, right: d.paceText ?? "", resetSide: .left)])
        #expect(MeterView.footerLines(d, theme: .instrument) == [.init(left: d.resetText, right: d.paceText ?? "idle", resetSide: .left)])
    }
}
