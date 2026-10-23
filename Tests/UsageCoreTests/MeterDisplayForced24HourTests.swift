import XCTest
@testable import UsageCore

/// Simulates iOS Settings > General > Date & Time > 24-Hour Time (AppleICUForce24HourTime) so that
/// `Locale.current` carries the forced-24h user override, then checks the app's On/Off setting still wins.
final class MeterDisplayForced24HourTests: XCTestCase {
    private static let keys = ["AppleICUForce24HourTime", "AppleLocale"]

    override func setUpWithError() throws {
        UserDefaults.standard.set(true, forKey: "AppleICUForce24HourTime")
        UserDefaults.standard.set("en_US", forKey: "AppleLocale")
        Self.reloadCurrentLocale()
        XCTAssertEqual(Self.rawPattern("h:mm a", Locale.current), "23:59",
                       "precondition: Locale.current must be forced to 24-hour")
    }

    override func tearDown() {
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        Self.reloadCurrentLocale()
    }

    func testOffGives12HourUnderForced24HourDevice() {
        XCTAssertEqual(MeterDisplay.clockText(Self.lateEvening, options: options(use24Hour: false)), "11:59 PM")
    }

    func testOnGives24HourUnderForced24HourDevice() {
        XCTAssertEqual(MeterDisplay.clockText(Self.lateEvening, options: options(use24Hour: true)), "23:59")
    }

    func testWeekdayResetHonoursOffUnderForced24HourDevice() {
        let now = Self.lateEvening.addingTimeInterval(-2 * 86_400)
        let m = Meter(kind: .weeklyAll, label: "All models", percentUsed: 39, resetsAt: Self.lateEvening, windowLength: .seconds(604_800))
        XCTAssertEqual(MeterDisplay.make(m, now: now, options: options(use24Hour: false)).resetText, "Resets Fri 11:59 PM")
    }

    // MARK: - Helpers

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }

    /// Fri 2026-10-23 23:59 Dublin.
    private static var lateEvening: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59))! }

    private func options(use24Hour: Bool) -> MeterDisplayOptions {
        MeterDisplayOptions(use24Hour: use24Hour, calendar: Self.cal, locale: .current)
    }

    private static func rawPattern(_ fmt: String, _ locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = cal.timeZone
        f.dateFormat = fmt
        return f.string(from: lateEvening)
    }

    /// Foundation caches `Locale.current`; the date-preferences notification makes it re-read the defaults.
    private static func reloadCurrentLocale() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("AppleDatePreferencesChangedNotification" as CFString),
            nil,
            nil,
            true
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
}
