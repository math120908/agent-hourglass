import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct GlassAccountCardTests {
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
        #expect(GlassAccountCard.retryText(date, options: options(.on)) == "Retry 14:46")
        #expect(GlassAccountCard.retryText(date, options: options(.off)) == "Retry 2:46 PM")
    }

    @Test func testRetrySystemFollowsLocale() {
        #expect(GlassAccountCard.retryText(date, options: options(.system, locale: "en_GB")) == "Retry 14:46")
        #expect(GlassAccountCard.retryText(date, options: options(.system, locale: "en_US")) == "Retry 2:46 PM")
    }

    @Test func testUltraHeadlineFallsBackToWeekly() {
        #expect(GlassAccountCard.headline(ultra, kind: .claude, now: date, options: options(.on))?.percentText == "27%")
        #expect(GlassAccountCard.headline(maxPlan, kind: .claude, now: date, options: options(.on))?.percentText == "34%")
    }
}
