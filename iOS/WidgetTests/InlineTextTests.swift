import XCTest
import UsageCore

final class InlineTextTests: XCTestCase {
    typealias F = WidgetFixtures

    func entry(at date: Date = F.now, status: AccountStatus? = .fresh, style: ResetStyle = .clock, snapshot: UsageSnapshot? = F.claudeMax) -> UsageEntry {
        var s = DisplaySettings.default
        s.resetStyle = style
        s.hour24 = .off
        return UsageEntry(date: date, account: nil, snapshot: snapshot, status: status, meterKeys: [], settings: s, theme: .glass, relevance: nil)
    }

    func text(_ e: UsageEntry) -> String { InlineText.text(e, calendar: F.calendar, locale: F.locale) }

    func testInlineClock() { XCTAssertEqual(text(entry()), "Claude 34% | 5:30 PM") }

    func testInlineCountdown() { XCTAssertEqual(text(entry(style: .countdown)), "Claude 34% | 2h 10m") }

    func testInlineStaleShowsAge() {
        XCTAssertEqual(text(entry(at: F.now.addingTimeInterval(45 * 60))), "Claude 34% | Updated 45 min ago")
    }

    func testInlineNeedsLogin() {
        XCTAssertEqual(text(entry(at: F.now.addingTimeInterval(120), status: .needsLogin)), "Claude 34% | Sign in | 2m")
    }

    func testInlineNoData() { XCTAssertEqual(text(entry(snapshot: nil)), "No data") }

    func testInlineNoSeparatorDot() {
        for e in [entry(), entry(style: .countdown), entry(at: F.now.addingTimeInterval(7200)), entry(status: .needsLogin), entry(snapshot: nil)] {
            XCTAssertFalse(text(e).contains("\u{00B7}"))
        }
    }
}
