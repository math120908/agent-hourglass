import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct InstrumentAccountRowTests {
    private let date = Date(timeIntervalSince1970: 1_792_853_160)  // 2026-10-24 14:46 UTC

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
}
