import Foundation
import Testing
@testable import AgentHourglass

struct WidgetReloaderTests {
    @Test func testReloadThrottle() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(WidgetReloader.shouldReload(lastReload: nil, now: t0))
        #expect(!WidgetReloader.shouldReload(lastReload: t0, now: t0.addingTimeInterval(30)))
        #expect(WidgetReloader.shouldReload(lastReload: t0, now: t0.addingTimeInterval(61)))
    }
}
