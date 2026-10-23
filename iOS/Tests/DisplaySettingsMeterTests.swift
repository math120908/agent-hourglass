import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct DisplaySettingsMeterTests {
    private func settings(_ h: Hour24, _ r: ResetStyle = .clock, remaining: Bool = false) -> DisplaySettings {
        DisplaySettings(showRemaining: remaining, resetStyle: r, hour24: h, refreshMinutes: 1)
    }

    @Test func testSystemHourFollowsLocale() {
        #expect(settings(.system).meterOptions(locale: Locale(identifier: "en_US")).use24Hour == false)
        #expect(settings(.system).meterOptions(locale: Locale(identifier: "en_GB")).use24Hour == true)
    }

    @Test func testExplicitHour24() {
        let us = Locale(identifier: "en_US")
        #expect(settings(.on).meterOptions(locale: us).use24Hour == true)
        #expect(settings(.off).meterOptions(locale: Locale(identifier: "en_GB")).use24Hour == false)
    }

    @Test func testResetStyleMapsToCountdown() {
        #expect(settings(.on, .countdown).meterOptions().countdown == true)
        #expect(settings(.on, .clock).meterOptions().countdown == false)
    }

    @Test func testPassesThroughRemainingCalendarLocale() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        let loc = Locale(identifier: "fr_FR")
        let o = settings(.on, remaining: true).meterOptions(calendar: cal, locale: loc)
        #expect(o.showRemaining == true)
        #expect(o.calendar == cal)
        #expect(o.locale == loc)
    }
}
