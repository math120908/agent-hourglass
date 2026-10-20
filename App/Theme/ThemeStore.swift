import Foundation
import Observation
import UsageCore

@MainActor @Observable
final class ThemeStore {
    private static let key = "theme"
    @ObservationIgnored private let defaults: UserDefaults

    var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(storedValue: defaults.string(forKey: Self.key))
    }
}
