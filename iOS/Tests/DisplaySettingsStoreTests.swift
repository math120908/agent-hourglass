import Foundation
import Testing
@testable import AgentHourglass

@MainActor @Test func testToggleResetStylePersists() {
    let suite = "test.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    let store = DisplaySettingsStore(defaults: d)
    #expect(store.settings.resetStyle == .clock)
    store.toggleResetStyle()
    #expect(DisplaySettingsStore(defaults: UserDefaults(suiteName: suite)!).settings.resetStyle == .countdown)
    store.toggleResetStyle()
    #expect(DisplaySettingsStore(defaults: UserDefaults(suiteName: suite)!).settings.resetStyle == .clock)
}
