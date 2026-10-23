#if DEBUG
import SwiftUI
import UsageCore

enum ClaudeSnapshots {
    /// Shape of a real pasted code; not a live value.
    private static let code = "ac_6f1b9c2e7d4a5f3b8e0c#9d2f7a1c4e8b6d3f5a0c2e"
    private static let incomplete = "ac_6f1b9c2e7d4a5f3b8e0c"

    static let scenes: [SnapshotScene] = [
        scene("claude-initial", .browsing, ClaudeSignInForm()),
        scene("claude-returned", .browsing, form(opened: true, hasStrings: true)),
        scene("claude-ready", .browsing, form(opened: true, text: code)),
        scene("claude-invalid", .browsing, form(opened: true, text: incomplete, showsInvalid: true)),
        scene("claude-exchanging", .exchanging, form(opened: true, text: code)),
        scene("claude-success", .success(AccountID(kind: .claude, remoteID: "demo")), form(opened: true)),
        scene("claude-failed", .failed("That code has expired. Sign in again."), form(opened: true)),
        scene("claude-ready-ax", .browsing, form(opened: true, text: code), typeSize: .accessibility2, height: 1300),
    ]

    private static func form(opened: Bool, hasStrings: Bool = false, text: String = "", showsInvalid: Bool = false) -> ClaudeSignInForm {
        ClaudeSignInForm(text: text, opened: opened, hasStrings: hasStrings, showsInvalid: showsInvalid)
    }

    private static func scene(
        _ name: String,
        _ state: ClaudeSignInModel.State,
        _ form: ClaudeSignInForm,
        typeSize: DynamicTypeSize = .large,
        height: CGFloat? = nil,
    ) -> SnapshotScene {
        // A taller frame for AX sizes so the bottom of the (scrolling) sheet shows in the render.
        let size: SnapshotSize = height == nil ? .device : .fitting(width: SnapshotSize.deviceSize.width)
        return SnapshotScene(name: name, size: size) { _ in
            AnyView(
                NavigationStack {
                    ClaudeSignInView(model: ClaudeSignInModel(state: state), form: form, onDone: { _ in })
                }
                .tint(GlassStyle.claude)
                .dynamicTypeSize(typeSize)
                .frame(height: height)
            )
        }
    }
}
#endif
