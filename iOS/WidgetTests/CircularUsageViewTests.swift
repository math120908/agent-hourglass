import XCTest
import UsageCore

final class CircularUsageViewTests: XCTestCase {
    typealias F = WidgetFixtures

    func entry(_ s: UsageSnapshot?, status: AccountStatus? = .fresh, at date: Date = F.now) -> UsageEntry {
        UsageEntry(date: date, account: nil, snapshot: s, status: status, meterKeys: [], settings: .default, theme: .glass, relevance: nil)
    }

    func content(_ e: UsageEntry) -> CircularUsageView.Content? {
        CircularUsageView.content(e, calendar: F.calendar, locale: F.locale)
    }

    func testFreshShowsShortLabel() {
        let c = content(entry(F.claudeMax))!
        XCTAssertEqual(c.row.key.rawValue, "session5h")
        XCTAssertEqual(c.caption, "5H")
        XCTAssertFalse(c.isProblem)
        XCTAssertFalse(c.isDimmed)
    }

    func testCenterDropsPercentAtThreeDigits() {
        XCTAssertEqual(CircularUsageView.centerText("100%"), "100")
        XCTAssertEqual(CircularUsageView.centerText("34%"), "34%")
    }

    func testStaleReplacesLabelWithAge() {
        let c = content(entry(F.claudeMax, at: F.now.addingTimeInterval(45 * 60)))!
        XCTAssertEqual(c.caption, "45m")
        XCTAssertTrue(c.isProblem)
    }

    func testNeedsLoginDimmedWithAge() {
        let c = content(entry(F.claudeMax, status: .needsLogin, at: F.now.addingTimeInterval(5 * 60)))!
        XCTAssertEqual(c.caption, "5m")
        XCTAssertTrue(c.isDimmed)
    }

    func testNoSnapshotIsNil() {
        XCTAssertNil(content(entry(nil)))
    }
}
