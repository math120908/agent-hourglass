import Foundation

/// Provider failures. Descriptions carry host and status only, never a query string or body.
public enum ProviderError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case http(status: Int, host: String, retryAfter: Duration?)
    case rateLimited(retryAfter: Duration?)
    case unauthorized
    case invalidGrant
    case schema(keys: [String])
    case transport(host: String)
    case hostNotAllowed(String)
    case redirectRefused(host: String)

    public var description: String {
        switch self {
        case let .http(status, host, _): "HTTP \(status) from \(host)"
        case let .rateLimited(retryAfter): "rate limited (retry after \(retryAfter.map { "\($0)" } ?? "unknown"))"
        case .unauthorized: "unauthorized"
        case .invalidGrant: "invalid grant"
        case let .schema(keys): "unexpected response shape (keys: \(keys.joined(separator: ", ")))"
        case let .transport(host): "network error talking to \(host)"
        case let .hostNotAllowed(host): "host not allowed for credentials: \(host)"
        case let .redirectRefused(host): "redirect refused on authenticated request to \(host)"
        }
    }

    public var errorDescription: String? { description }
}
