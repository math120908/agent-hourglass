import Foundation
import UsageCore

/// Wires the Codex device-code login into a `DeviceCodeFlowModel`.
enum CodexAddFlow {
    @MainActor static func model(app: AppModel) -> DeviceCodeFlowModel {
        model(app: app, auth: CodexDeviceAuth(http: app.http))
    }

    @MainActor static func model(app: AppModel, auth: CodexDeviceAuth) -> DeviceCodeFlowModel {
        let service = app.service
        let wake = DevicePollWake()
        return DeviceCodeFlowModel(
            title: "Codex",
            start: { try await auth.start() },
            complete: { prompt in
                let cred = try await auth.poll(prompt, wake: wake)
                // Restarted while the exchange was in flight: never add the old login's account.
                try Task.checkCancellation()
                return try await app.add { try await service.addCodex(credential: cred) }
            },
            wake: { wake.fire() },
        )
    }
}
