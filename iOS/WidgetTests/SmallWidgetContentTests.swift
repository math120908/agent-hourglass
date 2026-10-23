import XCTest
import UsageCore

final class SmallWidgetContentTests: XCTestCase {
    typealias F = WidgetFixtures
    let account = AccountEntry(id: AccountID(rawValue: "claude:max")!, kind: .claude, displayName: "Max", remoteLogin: nil, order: 0, addedAt: F.now, status: "ok")

    func entry(_ snap: UsageSnapshot?, status: AccountStatus? = .fresh, at: Date = F.now, account: AccountEntry? = nil) -> UsageEntry {
        UsageEntry(date: at, account: account ?? self.account, snapshot: snap, status: status, meterKeys: [], settings: .default, theme: .glass, relevance: nil)
    }

    func testFreshRowsAndAge() {
        let c = SmallWidgetContent(entry(F.claudeMax), calendar: F.calendar, locale: F.locale)
        XCTAssertEqual(c.rows.count, 2)
        XCTAssertEqual(c.rows.map(\.shortLabel), ["5H", "WK"])
        XCTAssertEqual(c.freshness, .fresh)
        XCTAssertFalse(c.isDimmed)
        XCTAssertNotNil(c.ageText)
    }

    func testStaleDerivedFromEntryDateNotDimmed() {
        let c = SmallWidgetContent(entry(F.claudeMax, at: F.now.addingTimeInterval(31 * 60)), calendar: F.calendar, locale: F.locale)
        XCTAssertEqual(c.freshness, .stale)
        XCTAssertFalse(c.isDimmed)
        XCTAssertEqual(AgeLabel.tone(c.freshness), .stale)
        XCTAssertEqual(AgeLabel.glyph(.stale), "clock")
    }

    func testNeedsLoginKeepsNumbersDimmedWithAge() {
        let c = SmallWidgetContent(entry(F.claudeMax, status: .needsLogin), calendar: F.calendar, locale: F.locale)
        XCTAssertEqual(c.rows.count, 2)
        XCTAssertTrue(c.isDimmed)
        XCTAssertNotNil(c.ageText)
        XCTAssertEqual(AgeLabel.tone(c.freshness), .signIn)
        XCTAssertEqual(AgeLabel.glyph(.signIn), "person.crop.circle.badge.exclamationmark")
    }

    func testEmptyCopy() {
        XCTAssertEqual(WidgetFreshness.emptyMessage(hasAccount: false), "Choose account")
        XCTAssertEqual(WidgetFreshness.emptyMessage(hasAccount: true), "No data yet")
    }

    func testNoSnapshotHasNoRowsNoAge() {
        let c = SmallWidgetContent(entry(nil), calendar: F.calendar, locale: F.locale)
        XCTAssertTrue(c.rows.isEmpty)
        XCTAssertNil(c.ageText)
        XCTAssertEqual(c.freshness, .noData)
    }
}
