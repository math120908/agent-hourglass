import XCTest

final class SmokeTests: XCTestCase {
    func testDisplaySettingsLoadDefaults() {
        let defaults = UserDefaults(suiteName: "p5-test-\(UUID())")!
        let s = DisplaySettings.load(from: defaults)
        XCTAssertFalse(s.showRemaining)
        XCTAssertEqual(s.resetStyle, .clock)
        XCTAssertEqual(s.hour24, .system)
    }
}
