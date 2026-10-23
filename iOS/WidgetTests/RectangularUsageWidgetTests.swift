import XCTest
import SwiftUI
import UsageCore

final class RectangularUsageWidgetTests: XCTestCase {
    typealias F = WidgetFixtures
    let account = AccountEntry(id: AccountID(rawValue: "claude:max")!, kind: .claude, displayName: "Max", remoteLogin: nil, order: 0, addedAt: F.now, status: "ok")

    func entry(_ keys: [String], status: AccountStatus? = .fresh, at date: Date = F.now, snapshot: UsageSnapshot? = F.claudeMax) -> UsageEntry {
        UsageEntry(date: date, account: account, snapshot: snapshot, status: status, meterKeys: keys.compactMap(MeterKey.init(rawValue:)), settings: .default, theme: .glass, relevance: nil)
    }

    func testOneRowShowsReset() {
        let c = RectangularUsageContent.make(entry(["session5h"]), calendar: F.calendar, locale: F.locale)!
        XCTAssertEqual(c.rows.count, 1)
        XCTAssertTrue(c.showReset)
        XCTAssertFalse(c.ageText.isEmpty)
    }

    func testMultipleRowsDropResetKeepAge() {
        let c = RectangularUsageContent.make(entry([]), calendar: F.calendar, locale: F.locale)!
        XCTAssertGreaterThanOrEqual(c.rows.count, 2)
        XCTAssertLessThanOrEqual(c.rows.count, 3)
        XCTAssertFalse(c.showReset)
        XCTAssertFalse(c.ageText.isEmpty)
    }

    func testStalenessDerivedFromEntryDate() {
        let late = F.now.addingTimeInterval(WidgetFreshness.staleAfter + 60)
        let c = RectangularUsageContent.make(entry([], at: late), calendar: F.calendar, locale: F.locale)!
        XCTAssertEqual(c.freshness, .stale)
    }

    func testNeedsLoginDimsValueButKeepsAge() {
        let c = RectangularUsageContent.make(entry([], status: .needsLogin), calendar: F.calendar, locale: F.locale)!
        XCTAssertEqual(c.freshness, .failed(.needsLogin))
        XCTAssertTrue(c.isDimmed)
        XCTAssertFalse(c.ageText.isEmpty)
    }

    func testNoSnapshotIsNil() {
        XCTAssertNil(RectangularUsageContent.make(entry([], snapshot: nil), calendar: F.calendar, locale: F.locale))
    }

    @MainActor func testViewBuilds() {
        let style = WidgetRenderStyle(mode: .accented, theme: .instrument, colorScheme: .dark)
        _ = RectangularUsageView(entry: entry([]), style: style).body
    }
}
