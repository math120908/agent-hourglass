#if DEBUG
import SwiftUI
import UsageCore

enum GrokSnapshots {
    private static let prompt = DeviceCodePrompt(
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://accounts.x.ai/device")!,
        interval: .seconds(5),
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        deviceCode: Secret("snapshot"),
    )

    static let scenes: [SnapshotScene] = [
        scene("grok-starting", .starting, CodexSignInForm()),
        scene("grok-waiting", .waiting(prompt), CodexSignInForm()),
        scene("grok-finishing", .waiting(prompt), CodexSignInForm(copied: true, opened: true, returnedAt: .now)),
        scene("grok-failed", .failed("Sign-in was denied"), done),
        scene("grok-success", .success(AccountID(kind: .grok, remoteID: "demo")), done),
    ]

    private static let done = CodexSignInForm(copied: true, opened: true)

    private static func scene(_ name: String, _ state: DeviceCodeFlowModel.State, _ form: CodexSignInForm) -> SnapshotScene {
        SnapshotScene(name: name, size: .device) { _ in
            AnyView(
                NavigationStack {
                    DeviceCodeSheet(model: DeviceCodeFlowModel(title: "Grok", kind: .grok, host: "x.ai", state: state), form: form) { _ in }
                }
                .tint(GlassStyle.fill(.grok))
            )
        }
    }
}
#endif
