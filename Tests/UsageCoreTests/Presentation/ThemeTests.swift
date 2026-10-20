import Testing
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
}
