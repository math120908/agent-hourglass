#if DEBUG
import SwiftUI
import UsageCore

enum DeviceCodeSnapshots {
    static let scenes: [SnapshotScene] = [
        scene("device-waiting", .waiting(prompt)),
        scene("device-expired", .expired),
        scene("device-success", .success(AccountID(kind: .codex, remoteID: "demo"))),
        scene("device-failed", .failed("Sign-in failed")),
    ]

    private static let prompt = DeviceCodePrompt(
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        interval: .seconds(5),
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        deviceCode: Secret("snapshot"),
    )

    private static func scene(_ name: String, _ state: DeviceCodeFlowModel.State) -> SnapshotScene {
        SnapshotScene(name: name, size: .device) { theme in
            AnyView(
                NavigationStack {
                    DeviceCodeSheet(model: DeviceCodeFlowModel(title: "Add Codex account", state: state), provider: .codex) { _ in }
                }
                .appTheme(theme)
                .tint(GlassStyle.codex)
            )
        }
    }
}
#endif
