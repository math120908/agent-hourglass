import Foundation
import UsageCore

/// Wires the Codex device-code login into a `DeviceCodeFlowModel`.
enum CodexAddFlow {
    @MainActor static func model(app: AppModel) -> DeviceCodeFlowModel {
        model(app: app, auth: CodexDeviceAuth(http: app.http))
    }

    @MainActor static func model(app: AppModel, auth: CodexDeviceAuth) -> DeviceCodeFlowModel {
        let service = app.service
        return DeviceCodeFlowModel(
            title: "Codex",
            start: { try await auth.start() },
            complete: { prompt in
                let id = try await service.addCodex(credential: try await auth.poll(prompt))
                await app.accountAdded(id)
                return id
            }
        )
    }
}
