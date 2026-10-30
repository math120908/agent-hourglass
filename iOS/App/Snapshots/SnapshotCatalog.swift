#if DEBUG
import SwiftUI
import UsageCore

struct SnapshotScene {
    let name: String
    let size: SnapshotSize
    var themes: [Theme] = Theme.allCases
    let make: @MainActor (Theme) -> AnyView
}

enum SnapshotSize {
    case device
    case fitting(width: CGFloat)

    static let deviceSize = CGSize(width: 402, height: 874)
}

enum SnapshotCatalog {
    static var all: [SnapshotScene] {
        MeterSnapshots.scenes
            + CardSnapshots.scenes
            + CardSnapshots.instrumentScenes
            + HomeSnapshots.scenes
            + CodexSnapshots.scenes
            + ClaudeSnapshots.scenes
            + GoogleSnapshots.scenes
            + AddMenuSnapshots.scenes
            + SettingsSnapshots.scenes
            + AboutSnapshots.scenes
    }
}
#endif
