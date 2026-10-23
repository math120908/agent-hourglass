import XCTest
import UsageCore

final class WidgetMeterModelTests: XCTestCase {
    typealias F = WidgetFixtures
    let session = F.claudeMax.meters[0]
    let weekly = F.claudeMax.meters[1]

    func key(_ s: String) -> MeterKey { MeterKey(rawValue: s)! }

    func row(_ m: Meter, at date: Date = F.now, _ settings: DisplaySettings = .default) -> WidgetMeterRow {
        WidgetMeterModel.row(m, at: date, settings: settings, calendar: F.calendar, locale: F.locale)
    }

    func testMeterKeyRawValues() {
        XCTAssertEqual(MeterKey(F.claudeMax.meters[2]).rawValue, "weeklyModel:Opus")
        XCTAssertEqual(MeterKey(F.codexPlus.meters[1]).rawValue, "window:604800")
        XCTAssertEqual(MeterKey(session).rawValue, "session5h")
        XCTAssertTrue(key("weeklyAll").matches(weekly))
        XCTAssertFalse(key("weeklyAll").matches(session))
        let data = try! JSONEncoder().encode([key("window:18000")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"window:18000\"]")
    }

    func testRowMatchesMeterDisplay() {
        for remaining in [false, true] {
            for style in [ResetStyle.clock, .countdown] {
                for h in [Hour24.on, .off] {
                    let s = DisplaySettings(showRemaining: remaining, resetStyle: style, hour24: h, refreshMinutes: 1)
                    for m in F.allMeters {
                        let d = MeterDisplay.make(m, now: F.now, options: s.meterOptions(calendar: F.calendar, locale: F.locale))
                        let r = row(m, s)
                        XCTAssertEqual(r.label, d.label)
                        XCTAssertEqual(r.percentText, d.percentText)
                        XCTAssertEqual(r.fraction, d.fraction)
                        XCTAssertEqual(r.paceTick, d.paceTick)
                        XCTAssertEqual(r.severity, d.severity)
                        XCTAssertEqual(r.resetText, d.resetShort ?? d.resetText)
                        XCTAssertEqual(r.key, MeterKey(m))
                    }
                }
            }
        }
    }

    func testRowUsedMode() { XCTAssertEqual(row(weekly).percentText, "61%") }

    func testRowRemainingMode() {
        var s = DisplaySettings.default
        s.showRemaining = true
        XCTAssertEqual(row(weekly, s).percentText, "39%")
    }

    func testResetCountdown() {
        var s = DisplaySettings.default
        s.resetStyle = .countdown
        XCTAssertEqual(row(session, s).resetText, "2h 10m")
        XCTAssertFalse(row(session, s).isDimmed)
    }

    func testShortLabels() {
        XCTAssertEqual(F.allMeters.map { row($0).shortLabel }, ["5H", "WK", "Opus W", "5H", "WK", "PREM", "PREM"])
        XCTAssertEqual(WidgetMeterModel.shortLabel(F.claudeMax.meters[2]), "Opus W")
        XCTAssertLessThanOrEqual(WidgetMeterModel.shortLabel(Meter(kind: .weeklyModel, label: "Sonnet", percentUsed: 1)).count, 6)
    }

    func testAfterResetRowIsDimmedAndSaysResetting() {
        let r = row(session, at: F.now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(r.resetText, "Resetting…")
        XCTAssertTrue(r.isDimmed)
    }

    func testResolveMetersSkipsMissingAndFallsBack() {
        let a = WidgetMeterModel.resolveMeters([key("weeklyModel:Sonnet"), key("weeklyAll")], in: F.claudeMax, family: .rectangular)
        XCTAssertEqual(a.map(MeterKey.init), [key("weeklyAll")])
        let b = WidgetMeterModel.resolveMeters([key("weeklyModel:Sonnet")], in: F.claudeMax, family: .small)
        XCTAssertEqual(b.map(MeterKey.init), [key("session5h"), key("weeklyAll")])
        let c = WidgetMeterModel.resolveMeters([], in: F.claudeMax, family: .rectangular)
        XCTAssertEqual(c.map(MeterKey.init), [key("session5h"), key("weeklyAll"), key("weeklyModel:Opus")])
        let d = WidgetMeterModel.resolveMeters([key("weeklyAll"), key("session5h")], in: F.claudeMax, family: .circular)
        XCTAssertEqual(d.map(MeterKey.init), [key("weeklyAll")])
    }

    func testDefaultsPerFamily() {
        XCTAssertEqual(WidgetMeterModel.defaultKeys(for: .claude, family: .small), [key("session5h"), key("weeklyAll")])
        XCTAssertEqual(WidgetMeterModel.defaultKeys(for: .claude, family: .circular), [key("session5h")])
        XCTAssertEqual(WidgetMeterModel.defaultKeys(for: .codex, family: .rectangular), [key("window:18000"), key("window:604800")])
        XCTAssertEqual(WidgetMeterModel.defaultKeys(for: .copilot, family: .rectangular), [key("copilotPremium")])
        XCTAssertEqual([WidgetFamilyKind.small, .circular, .rectangular, .inline].map(\.maxRows), [2, 1, 3, 1])
    }

    func testVisibleMeters() {
        XCTAssertEqual(WidgetMeterModel.visibleMeters(F.claudeMax), MeterDisplay.visibleMeters(F.claudeMax))
    }
}
