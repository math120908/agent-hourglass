#if DEBUG
import SwiftUI
import UsageCore

enum CodexSnapshots {
    private static let prompt = DeviceCodePrompt(
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        interval: .seconds(5),
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        deviceCode: Secret("snapshot"),
    )

    static let scenes: [SnapshotScene] = [
        scene("codex-starting", .starting, CodexSignInForm()),
        scene("codex-waiting", .waiting(prompt), CodexSignInForm()),
        scene("codex-copied", .waiting(prompt), CodexSignInForm(copied: true)),
        scene("codex-finishing", .waiting(prompt), CodexSignInForm(copied: true, opened: true, returnedAt: .now)),
        scene("codex-still-waiting", .waiting(prompt), CodexSignInForm(copied: true, opened: true, returnedAt: .now.addingTimeInterval(-40))),
        scene("codex-expired", .expired, done),
        scene("codex-failed", .failed("Sign-in failed"), done),
        scene("codex-success", .success(AccountID(kind: .codex, remoteID: "demo")), done),
        scene("codex-still-waiting-ax", .waiting(prompt), CodexSignInForm(copied: true, opened: true, returnedAt: .now.addingTimeInterval(-40)), typeSize: .accessibility2, height: 1500),
    ]

    private static let done = CodexSignInForm(copied: true, opened: true)

    private static func scene(
        _ name: String,
        _ state: DeviceCodeFlowModel.State,
        _ form: CodexSignInForm,
        typeSize: DynamicTypeSize = .large,
        height: CGFloat? = nil,
    ) -> SnapshotScene {
        let size: SnapshotSize = height == nil ? .device : .fitting(width: SnapshotSize.deviceSize.width)
        return SnapshotScene(name: name, size: size) { _ in
            AnyView(
                NavigationStack {
                    DeviceCodeSheet(model: DeviceCodeFlowModel(title: "Codex", state: state), form: form) { _ in }
                }
                .tint(GlassStyle.codexFill)
                .dynamicTypeSize(typeSize)
                .frame(height: height)
            )
        }
    }
}
#endif
