#if DEBUG
import SwiftUI
import UsageCore

enum SettingsSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "settings", size: .device) { theme in screen(theme) },
        SnapshotScene(name: "settings-editing", size: .device) { theme in screen(theme, editMode: .active) },
    ]

    @MainActor private static func screen(_ theme: Theme, editMode: EditMode = .inactive) -> AnyView {
        let defaults = UserDefaults(suiteName: "snapshot-settings-\(UUID().uuidString)")!
        defaults.set(theme.rawValue, forKey: ThemeStore.key)
        return AnyView(NavigationStack {
            SettingsView(
                model: .preview(),
                display: DisplaySettingsStore(defaults: defaults),
                themes: ThemeStore(defaults: defaults),
                editMode: editMode
            )
        })
    }
}
#endif
