#if DEBUG
import SwiftUI
import UsageCore

enum HomeSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "home", size: .device) { _ in home(Fixtures.appState()) },
        SnapshotScene(name: "home-attention", size: .device) { _ in
            let state = Fixtures.appState(statuses: [Fixtures.eevee: .needsLogin, Fixtures.mewtwo: .stale])
            state.snapshots[Fixtures.mewtwo]?.fetchedAt = Fixtures.now.addingTimeInterval(-23 * 60)
            return home(state)
        },
        SnapshotScene(name: "home-offline", size: .device) { _ in
            let state = Fixtures.appState(statuses: Dictionary(uniqueKeysWithValues: Fixtures.entries.map { ($0.id, AccountStatus.offline) }))
            state.isOffline = true
            return home(state)
        },
        SnapshotScene(name: "home-empty", size: .device) { _ in home(AppState(), entries: []) },
    ]

    @MainActor private static func home(_ state: AppState, entries: [AccountEntry] = Fixtures.entries) -> AnyView {
        var settings = DisplaySettings.default
        settings.hour24 = .on
        let add = Menu {
            Button("Claude") {}
            Button("Codex") {}
        } label: {
            Image(systemName: "plus")
        }
        return AnyView(
            HomeContent(
                state: state,
                entries: entries,
                settings: settings,
                now: Fixtures.now,
                addMenu: AnyView(add),
                focused: .constant(nil),
                actions: { _ in CardActions() },
                openSettings: {},
                refresh: {},
                calendar: Fixtures.calendar
            )
        )
    }
}
#endif
