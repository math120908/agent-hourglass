import Foundation
import Testing
@testable import UsageCore

struct HistorySummaryFormattingTests {
    @Test func headerStrings() {
        let s = RangeSummary(peakSession: 37.4, windowsOver90: 1, weeklyAtEnd: 38.6)
        let h = HistorySummaryFormatting(summary: s, isEmpty: false)
        #expect(h.weeklyNow == "39%")
        #expect(h.peakSession == "37%")
        #expect(h.windowsHit90 == "1 window hit 90%")
        #expect(HistorySummaryFormatting(summary: RangeSummary(peakSession: 90, windowsOver90: 3, weeklyAtEnd: nil), isEmpty: false).windowsHit90 == "3 windows hit 90%")
        let e = HistorySummaryFormatting(summary: nil, isEmpty: true)
        #expect(e.weeklyNow == "--")
        #expect(e.peakSession == "--")
        #expect(e.windowsHit90 == "No data")
    }

    @Test func rangeLabel() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm"
        let a = f.date(from: "2026-10-19 14:42")!, b = f.date(from: "2026-10-20 14:42")!
        let utc = TimeZone(identifier: "UTC")!
        #expect(HistorySummaryFormatting.rangeLabel(DateInterval(start: a, end: b), isNow: true, timeZone: utc) == "Oct 19 14:42 to Now")
        #expect(HistorySummaryFormatting.rangeLabel(DateInterval(start: a, end: b), isNow: false, timeZone: utc) == "Oct 19 14:42 to Oct 20 14:42")
    }
}
