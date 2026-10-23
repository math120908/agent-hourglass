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
        XCTAssertTrue(c.caption.hasPrefix("5H | "), c.caption)
        XCTAssertGreaterThan(c.caption.count, "5H | ".count)
        XCTAssertFalse(c.isProblem)
        XCTAssertFalse(c.isDimmed)
    }

    func testCenterDropsPercentAtThreeDigits() {
        XCTAssertEqual(CircularUsageView.centerText("100%"), "100")
        XCTAssertEqual(CircularUsageView.centerText("34%"), "34%")
    }

    func testStaleReplacesLabelWithAge() {
        let c = content(entry(F.claudeMax, at: F.now.addingTimeInterval(45 * 60)))!
        XCTAssertEqual(c.caption, "5H | 45m")
        XCTAssertTrue(c.isProblem)
    }

    func testNeedsLoginDimmedWithAge() {
        let c = content(entry(F.claudeMax, status: .needsLogin, at: F.now.addingTimeInterval(5 * 60)))!
        XCTAssertEqual(c.caption, "5H | 5m")
        XCTAssertTrue(c.isDimmed)
    }

    func testNoSnapshotIsNil() {
        XCTAssertNil(content(entry(nil)))
    }

    func testRingTickStaysOnRing() {
        let c = CGPoint(x: 50, y: 50)
        for f in [0, 0.001, 0.25, 0.5, 0.62, 0.999, 1, -0.2, 1.3] {
            let p = WidgetRing.point(on: f, center: c, radius: 40)
            XCTAssertEqual(hypot(p.x - 50, p.y - 50), 40, accuracy: 0.001, "fraction \(f)")
        }
        let top = WidgetRing.point(on: 0, center: c, radius: 40)
        XCTAssertEqual(top.x, 50, accuracy: 0.001); XCTAssertEqual(top.y, 10, accuracy: 0.001)
        let right = WidgetRing.point(on: 0.25, center: c, radius: 40)
        XCTAssertEqual(right.x, 90, accuracy: 0.001); XCTAssertEqual(right.y, 50, accuracy: 0.001)
        let nearOne = WidgetRing.point(on: 0.999, center: c, radius: 40)
        XCTAssertLessThan(nearOne.x, 50); XCTAssertLessThan(nearOne.y, 11)
        XCTAssertEqual(WidgetRing.point(on: 1.3, center: c, radius: 40).y, 10, accuracy: 0.001)
    }
}
