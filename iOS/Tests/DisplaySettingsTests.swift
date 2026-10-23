import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

private func storeRaw(_ json: String, in d: UserDefaults) {
    d.set(Data(json.utf8), forKey: DisplaySettings.key)
}

@Test func missingKeyLoadsDefaults() {
    let d = freshDefaults()
    #expect(DisplaySettings.load(from: d) == .default)
}

@Test func roundTrip() {
    let d = freshDefaults()
    let s = DisplaySettings(showRemaining: true, resetStyle: .countdown, hour24: .on, refreshMinutes: 5)
    s.save(to: d)
    #expect(DisplaySettings.load(from: d) == s)
}

@Test func corruptDataFallsBackToDefaults() {
    let d = freshDefaults()
    storeRaw("not json", in: d)
    #expect(DisplaySettings.load(from: d) == .default)
}

@Test func unknownEnumValueFallsBackToDefaults() {
    let d = freshDefaults()
    storeRaw(#"{"showRemaining":true,"resetStyle":"sundial","hour24":"on","refreshMinutes":5}"#, in: d)
    #expect(DisplaySettings.load(from: d) == .default)
}

@Test(arguments: [(0, 1), (3, 2), (99, 15)])
func refreshMinutesSnapsToAllowed(stored: Int, expected: Int) {
    let d = freshDefaults()
    storeRaw(#"{"showRemaining":false,"resetStyle":"clock","hour24":"system","refreshMinutes":\#(stored)}"#, in: d)
    #expect(DisplaySettings.load(from: d).refreshMinutes == expected)
}

@MainActor @Test func themeStoreWritesWhereWidgetReads() {
    let d = freshDefaults()
    let store = ThemeStore(defaults: d)
    store.theme = .instrument
    #expect(Theme.current(in: d) == .instrument)
}
