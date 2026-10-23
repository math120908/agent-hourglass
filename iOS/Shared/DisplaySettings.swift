import Foundation
import UsageCore

enum ResetStyle: String, Codable, Sendable { case clock, countdown }

enum Hour24: String, Codable, Sendable { case system, on, off }

/// Display preferences shared by app and widget, stored as JSON under `displaySettings`.
struct DisplaySettings: Codable, Equatable, Sendable {
    var showRemaining: Bool
    var resetStyle: ResetStyle
    var hour24: Hour24
    var refreshMinutes: Int

    static let key = "displaySettings"
    static let allowedRefreshMinutes = [1, 2, 5, 10, 15]
    static let `default` = DisplaySettings(showRemaining: false, resetStyle: .clock, hour24: .system, refreshMinutes: 1)

    /// Missing or undecodable data yields `.default`; `refreshMinutes` snaps to the
    /// nearest allowed value (lower on tie).
    static func load(from defaults: UserDefaults) -> DisplaySettings {
        guard let data = defaults.data(forKey: key),
              var s = try? JSONDecoder().decode(DisplaySettings.self, from: data)
        else { return .default }
        s.refreshMinutes = snap(s.refreshMinutes)
        return s
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func snap(_ minutes: Int) -> Int {
        // min(by:) returns the first minimum, and the list is ascending, so ties go lower.
        allowedRefreshMinutes.min { abs($0 - minutes) < abs($1 - minutes) }!
    }
}

extension ThemeStore {
    /// App-side store backed by the App Group defaults.
    @MainActor static func appGroup() -> ThemeStore { ThemeStore(defaults: AppGroup.defaults) }
}

extension Theme {
    /// Widget-side read of the stored theme; no MainActor needed.
    static func current(in defaults: UserDefaults) -> Theme {
        Theme(storedValue: defaults.string(forKey: ThemeStore.key))
    }
}
