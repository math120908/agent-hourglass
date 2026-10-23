import XCTest
import UsageCore

final class WidgetFreshnessTests: XCTestCase {
    typealias F = WidgetFixtures
    func ago(_ s: TimeInterval) -> Date { F.now.addingTimeInterval(-s) }
    func fresh(_ age: TimeInterval?, _ st: AccountStatus? = nil) -> WidgetFreshness.Freshness {
        WidgetFreshness.freshness(fetchedAt: age.map(ago), status: st, at: F.now)
    }

    func testFreshnessRules() {
        XCTAssertEqual(WidgetFreshness.staleAfter, 2 * WidgetFreshness.expectedRefresh)
        XCTAssertEqual(fresh(nil), .noData)
        XCTAssertEqual(fresh(nil, .needsLogin), .noData)
        XCTAssertEqual(fresh(60, .needsLogin), .failed(.needsLogin))
        XCTAssertEqual(fresh(60, .codexNotSignedIn), .failed(.codexNotSignedIn))
        XCTAssertEqual(fresh(3 * 3600, .schemaError), .failed(.schemaError))
        XCTAssertEqual(fresh(29 * 60), .fresh)
        XCTAssertEqual(fresh(31 * 60), .stale)
        XCTAssertEqual(fresh(31 * 60, .offline), .stale)
        XCTAssertEqual(fresh(60, .offline), .fresh)
        XCTAssertEqual(fresh(60, .rateLimited(retryAt: F.now)), .fresh)
    }

    func testAgeText() {
        var s = DisplaySettings.default
        s.hour24 = .on
        func age(_ a: TimeInterval) -> String {
            WidgetFreshness.ageText(fetchedAt: ago(a), at: F.now, calendar: F.calendar, settings: s)
        }
        XCTAssertEqual(age(30), "now")
        XCTAssertEqual(age(12 * 60), "12m")
        XCTAssertEqual(age(3 * 3600), "12:20")
        XCTAssertEqual(age(3 * 3600), MeterDisplay.ageShort(fetchedAt: ago(3 * 3600), now: F.now, options: s.meterOptions(calendar: F.calendar)))
    }
}
