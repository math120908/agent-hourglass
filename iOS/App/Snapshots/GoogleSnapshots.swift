#if DEBUG
import SwiftUI
import UsageCore

enum GoogleSnapshots {
    static let scenes: [SnapshotScene] = [
        scene("google-initial", .idle),
        scene("google-waiting", .waiting),
        scene("google-success", .success(AccountID(kind: .google, remoteID: "demo"))),
        scene("google-failed", .failed("Google rejected the Antigravity client. Retry")),
        scene("google-initial-ax", .idle, typeSize: .accessibility2, height: 1100),
    ]

    private static func scene(
        _ name: String,
        _ state: GoogleSignInModel.State,
        typeSize: DynamicTypeSize = .large,
        height: CGFloat? = nil,
    ) -> SnapshotScene {
        let size: SnapshotSize = height == nil ? .device : .fitting(width: SnapshotSize.deviceSize.width)
        return SnapshotScene(name: name, size: size) { _ in
            AnyView(
                NavigationStack {
                    GoogleSignInView(model: GoogleSignInModel(state: state)) { _ in }
                }
                .tint(GlassStyle.fill(.google))
                .dynamicTypeSize(typeSize)
                .frame(height: height)
            )
        }
    }
}
#endif
