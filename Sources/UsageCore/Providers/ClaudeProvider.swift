import Foundation

public struct ClaudeProvider: UsageProvider {
    public let kind: ProviderKind = .claude
    public let minimumInterval: Duration = .seconds(60)

    public init() {}

    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        var req = URLRequest(url: ClaudeOAuth.usageURL)
        req.setValue(ClaudeOAuth.betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await http.send(req, bearer: credential.access)
        // The account id is assigned by the caller; a placeholder keeps decoding pure.
        return try Self.decodeUsage(data, accountID: AccountID(kind: .claude, remoteID: "unknown"), now: Date())
    }

    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        guard let refresh = credential.refresh else { throw ProviderError.invalidGrant }
        var req = URLRequest(url: ClaudeOAuth.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refresh.reveal(),
            "client_id": ClaudeOAuth.clientID,
        ])
        let data: Data
        do {
            (data, _) = try await http.send(req, bearer: nil)
        } catch ProviderError.http(status: 400, _, _) {
            throw ProviderError.invalidGrant
        }
        let (fresh, _, _) = try Self.decodeTokenResponse(data, now: Date())
        return fresh
    }
}
