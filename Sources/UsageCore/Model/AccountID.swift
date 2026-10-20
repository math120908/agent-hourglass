/// Stable account key, `"<kind>:<remoteID>"`.
public struct AccountID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) { self.rawValue = rawValue }

    public init(kind: ProviderKind, remoteID: String) { rawValue = "\(kind.rawValue):\(remoteID)" }

    public var kind: ProviderKind? {
        guard let prefix = rawValue.split(separator: ":", maxSplits: 1).first else { return nil }
        return ProviderKind(rawValue: String(prefix))
    }
}
