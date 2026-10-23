#if DEBUG
import SwiftUI

enum AboutSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "about", size: .device) { _ in
            AnyView(NavigationStack { AboutView(diagnostics: { "" }) })
        },
        SnapshotScene(name: "about-copied", size: .device) { _ in
            AnyView(NavigationStack { AboutView(diagnostics: { "" }, copied: true) })
        },
    ]
}
#endif
