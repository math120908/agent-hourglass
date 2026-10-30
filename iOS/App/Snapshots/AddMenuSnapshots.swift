#if DEBUG
import SwiftUI

enum AddMenuSnapshots {
    static let scenes: [SnapshotScene] = [
        menu("add-menu", google: false, height: 204),
        // A dev build with the Google client secret (SPIKE).
        menu("add-menu-google", google: true, height: 254),
    ]

    private static func menu(_ name: String, google: Bool, height: CGFloat) -> SnapshotScene {
        SnapshotScene(name: name, size: .fitting(width: 402)) { theme in
            AnyView(
                List { AddAccountItems(present: .constant(nil), google: google) }
                    .listStyle(.insetGrouped)
                    .scrollDisabled(true)
                    .frame(height: height)
                    .appTheme(theme)
            )
        }
    }
}
#endif
