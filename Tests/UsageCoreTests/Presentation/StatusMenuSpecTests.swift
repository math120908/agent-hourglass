import Testing
@testable import UsageCore

struct StatusMenuSpecTests {
    @Test func titlesInOrderWithSeparatorBeforeQuit() {
        let titles = StatusMenuItem.layout.map { $0?.title ?? "---" }
        #expect(titles == ["Refresh Now", "Open History…", "Settings…", "---", "Quit Claude Usage"])
    }

    @Test func clickRouting() {
        #expect(!StatusMenuItem.opensMenu(isRightMouseUp: false, controlHeld: false))
        #expect(StatusMenuItem.opensMenu(isRightMouseUp: true, controlHeld: false))
        #expect(StatusMenuItem.opensMenu(isRightMouseUp: false, controlHeld: true))
    }
}
