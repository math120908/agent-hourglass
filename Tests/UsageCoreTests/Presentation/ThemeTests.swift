import Testing
import Foundation
import Observation
@testable import UsageCore

@Suite struct ThemeTests {
    @Test func defaultIsGlass() {
        #expect(Theme.default == .glass)
        #expect(Theme(storedValue: nil) == .glass)
    }

    @Test func unknownStoredValueFallsBack() {
        #expect(Theme(storedValue: "instrument-v9") == .glass)
    }

    @Test func roundTrip() {
        for theme in Theme.allCases {
            #expect(Theme(storedValue: theme.rawValue) == theme)
        }
    }

    @Test func instrumentRoundTrip() {
        #expect(Theme(storedValue: "instrument") == .instrument)
        #expect(Theme.instrument.rawValue == "instrument")
    }

    @Test func allCasesOrder() {
        #expect(Theme.allCases == [.glass, .instrument])
    }
}

@MainActor @Suite struct ThemeStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ThemeStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func storePersistsAndNotifies() {
        let d = freshDefaults()
        let store = ThemeStore(defaults: d)
        #expect(store.theme == .glass)
        let fired = FireCount()
        withObservationTracking { _ = store.theme } onChange: { fired.value += 1 }
        store.theme = .instrument
        #expect(d.string(forKey: ThemeStore.key) == "instrument")
        #expect(fired.value == 1)
        #expect(ThemeStore(defaults: d).theme == .instrument)
    }

    @Test func reloadPicksUpExternalWrite() {
        let d = freshDefaults()
        let store = ThemeStore(defaults: d)
        d.set("instrument", forKey: ThemeStore.key)
        store.reload()
        #expect(store.theme == .instrument)
        d.set("bogus", forKey: ThemeStore.key)
        store.reload()
        #expect(store.theme == .glass)
    }
}

private final class FireCount: @unchecked Sendable { var value = 0 }
