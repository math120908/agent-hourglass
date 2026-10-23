#if DEBUG
import SwiftUI
import UsageCore

enum ClaudeSnapshots {
    static let scenes: [SnapshotScene] = [
        scene("claude-signin", .browsing),
        scene("claude-exchanging", .exchanging),
        scene("claude-success", .success(AccountID(kind: .claude, remoteID: "demo"))),
        scene("claude-failed", .failed("Sign-in didn't match. Try again.")),
        paste("claude-paste-empty", ""),
        paste("claude-paste-filled", "PASTE-CODE#STATE"),
    ]

    private static func paste(_ name: String, _ text: String) -> SnapshotScene {
        SnapshotScene(name: name, size: .device) { theme in
            AnyView(
                NavigationStack {
                    ClaudePasteView(model: ClaudeSignInModel(state: .browsing), text: text, onDone: { _ in })
                }
                .appTheme(theme)
                .tint(GlassStyle.claude)
            )
        }
    }

    private static func scene(_ name: String, _ state: ClaudeSignInModel.State) -> SnapshotScene {
        SnapshotScene(name: name, size: .device) { theme in
            AnyView(
                NavigationStack {
                    ClaudeSignInSheet(
                        model: ClaudeSignInModel(state: state),
                        web: Rectangle().fill(Color.gray.opacity(0.3)),
                        onPasteInstead: {},
                        onDone: { _ in },
                    )
                }
                .appTheme(theme)
                .tint(GlassStyle.claude)
            )
        }
    }
}
#endif
