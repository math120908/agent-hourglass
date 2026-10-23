import XCTest

final class TimelinePlanTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStartsAtNow() {
        let dates = TimelinePlan.entryDates(now: now, resets: [], staleAt: nil)
        XCTAssertEqual(dates.first, now)
    }

    func testSpacing() {
        let dates = TimelinePlan.entryDates(now: now, resets: [], staleAt: nil)
        for (a, b) in zip(dates, dates.dropFirst()) {
            let gap = b.timeIntervalSince(a)
            if b.timeIntervalSince(now) <= 3600 {
                XCTAssertEqual(gap, 300)
            } else {
                XCTAssertEqual(gap, 900)
            }
        }
        XCTAssertEqual(dates.last, now.addingTimeInterval(TimelinePlan.horizon))
    }

    func testIncludesResetAndStaleDates() {
        let reset = now.addingTimeInterval(2 * 3600 + 420)
        let stale = now.addingTimeInterval(3 * 3600 + 120)
        let dates = TimelinePlan.entryDates(now: now, resets: [reset], staleAt: stale)
        XCTAssertTrue(dates.contains(reset))
        XCTAssertTrue(dates.contains(stale))
        XCTAssertEqual(dates, dates.sorted())
    }

    func testDropsDatesOutsideHorizon() {
        let past = now.addingTimeInterval(-600)
        let far = now.addingTimeInterval(TimelinePlan.horizon + 600)
        let dates = TimelinePlan.entryDates(now: now, resets: [past, far], staleAt: far)
        XCTAssertFalse(dates.contains(past))
        XCTAssertFalse(dates.contains(far))
        XCTAssertTrue(dates.allSatisfy { $0 >= now && $0 <= now.addingTimeInterval(TimelinePlan.horizon) })
    }

    func testDedupeWithin60s() {
        let reset = now.addingTimeInterval(330)
        let dates = TimelinePlan.entryDates(now: now, resets: [reset], staleAt: nil)
        XCTAssertFalse(dates.contains(reset))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(300)))
        for (a, b) in zip(dates, dates.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 60)
        }
    }

    func testCountAtMost45() {
        let resets = (1...6).map { now.addingTimeInterval(Double($0) * 3000 + 450) }
        let dates = TimelinePlan.entryDates(now: now, resets: resets, staleAt: now.addingTimeInterval(4000))
        XCTAssertLessThanOrEqual(dates.count, 45)
    }

    func testReloadDate() {
        XCTAssertEqual(TimelinePlan.reloadDate(now: now), now.addingTimeInterval(900))
    }
}
