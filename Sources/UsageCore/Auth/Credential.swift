import Foundation

public struct Credential: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var kind: ProviderKind
    public var access: Secret
    public var refresh: Secret?
    public var expiresAt: Date?
    public var refreshExpiresAt: Date?
    public var scopes: [String]

    public init(
        kind: ProviderKind,
        access: Secret,
        refresh: Secret?,
        expiresAt: Date?,
        refreshExpiresAt: Date?,
        scopes: [String]
    ) {
        self.kind = kind
        self.access = access
        self.refresh = refresh
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.scopes = scopes
    }

    public var description: String {
        let exp = expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
        return "Credential(\(kind.rawValue), expires \(exp))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["kind": kind, "expiresAt": expiresAt as Any, "scopes": scopes], displayStyle: .struct)
    }
}
