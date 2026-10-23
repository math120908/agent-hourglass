import XCTest
@testable import UsageCore

final class MeterDisplayTests: XCTestCase {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }
    static var weeklyReset: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23))! }
    static var now: Date { weeklyReset.addingTimeInterval(-0.48 * 7 * 86_400) }
    let week = Duration.seconds(7 * 86_400)
    var now: Date { Self.now }

    var allModels: Meter { Meter(kind: .weeklyAll, label: "All models", percentUsed: 39, resetsAt: Self.weeklyReset, windowLength: week) }
    var session: Meter { Meter(kind: .session5h, label: "Session", percentUsed: 1, resetsAt: now.addingTimeInterval(92 * 60), windowLength: .seconds(5 * 3600)) }
    var codex: Meter {
        Meter(kind: .window, label: Meter.windowLabel(seconds: 2_592_000), percentUsed: 12, resetsAt: now.addingTimeInterval(1_296_000), windowLength: .seconds(2_592_000))
    }
    var copilot: Meter {
        Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: 33.7, used: 84_250, limit: 250_000, resetsAt: Self.cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
    }
    var noReset: Meter { Meter(kind: .session5h, label: "Session", percentUsed: 1, windowLength: .seconds(5 * 3600)) }
    var pastReset: Meter { Meter(kind: .weeklyAll, label: "All models", percentUsed: 39, resetsAt: now.addingTimeInterval(-10), windowLength: week) }

    func opts(showRemaining: Bool = false, countdown: Bool = false, use24Hour: Bool = true) -> MeterDisplayOptions {
        MeterDisplayOptions(showRemaining: showRemaining, countdown: countdown, use24Hour: use24Hour, calendar: Self.cal, locale: Locale(identifier: "en_US"))
    }
    func make(_ m: Meter, _ o: MeterDisplayOptions) -> MeterDisplay { MeterDisplay.make(m, now: now, options: o) }
    func age(_ dt: TimeInterval) -> String { MeterDisplay.ageText(fetchedAt: now.addingTimeInterval(dt), now: now, options: opts()) }
    func short(_ dt: TimeInterval) -> String { MeterDisplay.ageShort(fetchedAt: now.addingTimeInterval(dt), now: now, options: opts()) }

    func testWeeklyClock24() {
        let d = make(allModels, opts(use24Hour: true))
        XCTAssertEqual(d.resetText, "Resets Fri 23:00"); XCTAssertEqual(d.resetShort, "Fri 23:00"); XCTAssertEqual(d.percentText, "39%")
        XCTAssertFalse(d.isRemaining)
        XCTAssertEqual(d.fraction!, 0.39, accuracy: 1e-9); XCTAssertEqual(d.paceTick!, 0.52, accuracy: 1e-6); XCTAssertEqual(d.paceText, "13% under pace")
    }
    func testWeeklyClock12() { XCTAssertEqual(make(allModels, opts(use24Hour: false)).resetText, "Resets Fri 11:00 PM") }
    func testWeeklyCountdown() {
        let d = make(allModels, opts(countdown: true))
        XCTAssertEqual(d.resetText, "Resets in 3d 8h"); XCTAssertEqual(d.resetShort, "3d 8h")
    }
    func testRemaining() {
        let d = make(allModels, opts(showRemaining: true))
        XCTAssertEqual(d.percentText, "61%"); XCTAssertTrue(d.isRemaining)
        XCTAssertEqual(d.fraction!, 0.61, accuracy: 1e-9); XCTAssertEqual(d.paceTick!, 0.48, accuracy: 1e-6); XCTAssertEqual(d.paceText, "13% under pace")
    }
    func testSessionSameDay() {
        XCTAssertEqual(make(session, opts(use24Hour: true)).resetText, "Resets 15:53")
        XCTAssertEqual(make(session, opts(use24Hour: false)).resetText, "Resets 3:53 PM")
        XCTAssertEqual(make(session, opts(countdown: true)).resetText, "Resets in 1h 32m")
        XCTAssertNil(make(session, opts()).paceTick)
    }
    func testShortCountdown() { XCTAssertEqual(MeterDisplay.make(session, now: session.resetsAt!.addingTimeInterval(-61), options: opts(countdown: true)).resetText, "Resets in 2m") }
    func testCodex30Day() {
        XCTAssertEqual(make(codex, opts()).resetText, "Resets Nov 4")
        XCTAssertEqual(make(codex, opts(countdown: true)).resetText, "Resets in 15d")
    }
    func testCopilot() {
        let d = make(copilot, opts())
        XCTAssertEqual(d.resetText, "Resets Nov 1")
        XCTAssertEqual(d.detailText, "84,250 / 250,000 credits (≈ $843 / $2,500)")
        XCTAssertEqual(make(copilot, opts(countdown: true)).resetText, "Resets in 11d 10h")
    }
    func testCopilotNotIncluded() {
        var m = copilot; m.limit = 0
        let d = make(m, opts())
        XCTAssertEqual(d.percentText, "Not included"); XCTAssertNil(d.fraction)
    }
    func testNotStartedAndResetting() {
        XCTAssertEqual(make(noReset, opts()).resetText, "Not started"); XCTAssertNil(make(noReset, opts()).resetShort)
        XCTAssertEqual(make(pastReset, opts()).resetText, "Resetting…"); XCTAssertNil(make(pastReset, opts()).resetShort)
    }
    func testAgeText() {
        XCTAssertEqual(age(-40), "Updated just now"); XCTAssertEqual(age(-180), "Updated 3 min ago")
        XCTAssertEqual(age(-3 * 3600), "Updated 11:21"); XCTAssertEqual(age(-2 * 86_400), "Updated Oct 18"); XCTAssertEqual(age(300), "Updated just now")
    }
    func testAgeShort() {
        XCTAssertEqual(short(-30), "now"); XCTAssertEqual(short(-720), "12m"); XCTAssertEqual(short(-3 * 3600), "11:21")
        XCTAssertEqual(short(-2 * 86_400), "Oct 18"); XCTAssertEqual(short(300), "now")
        XCTAssertEqual(MeterDisplay.ageShort(fetchedAt: now.addingTimeInterval(-3 * 3600), now: now, options: opts(use24Hour: false)), "11:21 AM")
    }
    func testVisibleMetersDropsUnlimited() {
        let snap = UsageSnapshot(accountID: AccountID(kind: .copilot, remoteID: "x"), fetchedAt: now, plan: nil, meters: [
            copilot,
            Meter(kind: .copilotChat, label: "Chat", percentUsed: 0, limit: 0),
            Meter(kind: .copilotCompletions, label: "Completions", percentUsed: nil, isUnlimited: true),
        ])
        XCTAssertEqual(MeterDisplay.visibleMeters(snap).map(\.label), ["Premium requests"])
        XCTAssertEqual(MeterDisplay.visibleMeters(nil), [])
    }
}
