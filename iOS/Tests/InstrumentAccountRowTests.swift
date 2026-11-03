import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct InstrumentAccountRowTests {
    private let date = Date(timeIntervalSince1970: 1_792_853_160)  // 2026-10-24 14:46 UTC

    private let ultra = [
        Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 27, windowLength: .seconds(604_800)),
        Meter(kind: .weeklyModel, label: "Opus", percentUsed: 9),
    ]
    private let maxPlan = [
        Meter(kind: .session5h, label: "Session", percentUsed: 34, windowLength: .seconds(18000)),
        Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 61, windowLength: .seconds(604_800)),
    ]

    private func options(_ h: Hour24, locale: String = "en_US") -> MeterDisplayOptions {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = DisplaySettings(showRemaining: false, resetStyle: .clock, hour24: h, refreshMinutes: 1)
        return s.meterOptions(calendar: cal, locale: Locale(identifier: locale))
    }

    @Test func testRetryFollows24HourSetting() {
        #expect(InstrumentAccountRow.retryText(date, options: options(.on, locale: "en_US")) == "Retry 14:46")
        #expect(InstrumentAccountRow.retryText(date, options: options(.off)) == "Retry 2:46 PM")
    }

    @Test func testUltraHeadlineFallsBackToWeekly() {
        #expect(InstrumentAccountRow.headline(ultra, kind: .claude, now: date, options: options(.on))?.percentText == "27%")
        #expect(InstrumentAccountRow.headline(maxPlan, kind: .claude, now: date, options: options(.on))?.percentText == "34%")
    }

    @Test func testUltraSubtitleIsWeekOnly() {
        #expect(InstrumentAccountRow.subtitle(ultra, kind: .claude, fetchedAt: date, now: date, options: options(.on)) == "Week 27%")
        #expect(InstrumentAccountRow.subtitle(maxPlan, kind: .claude, fetchedAt: date, now: date, options: options(.on)) == "Session 34% | Week 61%")
    }
}
