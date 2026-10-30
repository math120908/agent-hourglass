import Foundation
import UsageCore

/// Wires the Grok device-code login into a `DeviceCodeFlowModel`.
enum GrokAddFlow {
    @MainActor static func model(app: AppModel) -> DeviceCodeFlowModel {
        model(app: app, auth: GrokDeviceAuth(http: app.http))
    }

    @MainActor static func model(app: AppModel, auth: GrokDeviceAuth) -> DeviceCodeFlowModel {
        let service = app.service
        let wake = DevicePollWake()
        return DeviceCodeFlowModel(
            title: "Grok",
            kind: .grok,
            host: "x.ai",
            start: { try await auth.start() },
            complete: { prompt in
                let cred = try await auth.poll(prompt, wake: wake)
                // Restarted while the token POST was in flight: never add the old login's account.
                try Task.checkCancellation()
                return try await app.add { try await service.addGrok(credential: cred) }
            },
            wake: { wake.fire() },
            failureMessage: { error in
                if case .failed(let message) = AddFlowState.deviceFailure(error) { message } else { "Sign-in failed" }
            },
        )
    }
}
