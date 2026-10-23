import Foundation

/// What a device-code login shows the user, plus the handle used to poll for completion.
/// `deviceCode` is the polling handle (GitHub `device_code`, Codex `device_auth_id`).
public struct DeviceCodePrompt: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let userCode: String
    public let verificationURL: URL
    public let interval: Duration
    public let expiresAt: Date
    public let deviceCode: Secret

    public init(userCode: String, verificationURL: URL, interval: Duration, expiresAt: Date, deviceCode: Secret) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.expiresAt = expiresAt
        self.deviceCode = deviceCode
    }

    public var description: String {
        "DeviceCodePrompt(userCode: \(userCode), host: \(verificationURL.host ?? "?"), expiresAt: \(expiresAt))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "userCode": userCode,
                "host": verificationURL.host ?? "?",
                "expiresAt": expiresAt,
            ],
            displayStyle: .struct
        )
    }
}

public enum DeviceFlowError: Error, Equatable, Sendable {
    case expired
    case denied
    case unexpected(status: Int)
}
