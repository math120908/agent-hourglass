/// A secret string that never appears in descriptions, reflection, or dumps.
public struct Secret: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: String

    public init(_ value: String) { self.value = value }

    /// Returns the raw value. Callers are limited to CredentialStore and HTTPClient.
    public func reveal() -> String { value }

    public var description: String { "Secret(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }

    /// Encodes the raw string; only CredentialStore encodes credentials.
    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
