import Foundation

public protocol UsageProvider: Sendable {
    var kind: ProviderKind { get }
    /// Fetch one snapshot. Throws ProviderError; never returns partial garbage.
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot
    /// Exchange a refresh token. Copilot returns nil: its token is re-read from gh on every fetch.
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential?
    /// Lower bound on spacing between two fetches for one account, regardless of Settings.
    var minimumInterval: Duration { get }
}
