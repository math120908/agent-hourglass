#if DEBUG
import SwiftUI

enum AddMenuSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "add-menu", size: .fitting(width: 402)) { theme in
            AnyView(
                List { AddAccountItems(present: .constant(nil)) }
                    .listStyle(.insetGrouped)
                    .scrollDisabled(true)
                    .frame(height: 160)
                    .environment(\.appTheme, theme)
            )
        },
    ]
}
#endif
