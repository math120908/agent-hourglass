#if DEBUG
import SwiftUI
import UsageCore

enum SettingsSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "settings", size: .device) { theme in screen(theme) },
        SnapshotScene(name: "settings-editing", size: .device) { theme in
            AnyView(screen(theme).environment(\.editMode, .constant(.active)))
        },
        SnapshotScene(name: "settings-remove-confirm", size: .device) { theme in
            screen(theme, pendingRemove: Fixtures.entries[1])
        },
    ]

    @MainActor private static func screen(_ theme: Theme, pendingRemove: AccountEntry? = nil) -> AnyView {
        let defaults = UserDefaults(suiteName: "snapshot-settings-\(UUID().uuidString)")!
        defaults.set(theme.rawValue, forKey: ThemeStore.key)
        return AnyView(NavigationStack {
            SettingsView(
                model: .preview(),
                display: DisplaySettingsStore(defaults: defaults),
                themes: ThemeStore(defaults: defaults),
                pendingRemove: pendingRemove
            )
        })
    }
}
#endif
