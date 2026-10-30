import Foundation
import os

/// Grok (xAI) weekly credit pool from the Grok-CLI proxy (R10 §2a): `GET /v1/billing?format=credits`
/// for the meters, then `GET /v1/settings` (best effort) for the plan name. Owned device-login credential.
public struct GrokProvider: UsageProvider {
    public static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    public static let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!
    /// The proxy only serves requests that identify as the Grok CLI; send both.
    public static let clientHeaders: [String: String] = ["x-xai-token-auth": "xai-grok-cli", "x-grok-client-mode": "build"]
    /// String keys kept in debug logs: period type and bounds, product names, plan. Never identity or numeric user ids.
    static let logKeep: Set<String> = ["type", "product", "subscription_tier_display", "start", "end"]

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "GrokProvider")

    public let kind: ProviderKind = .grok
    /// R10 politeness: one request pair per account per 5 min at most.
    public let minimumInterval: Duration = .seconds(300)

    public init() {}

    /// Billing 403 → `QuotaError.unavailable`, never retried with other scopes (decision 7).
    /// A 401 on either call propagates as `.unauthorized` so `AccountClient` refreshes and retries once.
    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        guard let account = credential.remoteAccountID, !account.isEmpty else { throw ProviderError.invalidGrant }
        let billing: Data
        do {
            (billing, _) = try await http.send(Self.request(Self.billingURL), bearer: credential.access)
        } catch ProviderError.http(status: 403, _, _) {
            Self.log.error("billing 403")
            throw QuotaError.unavailable
        }
        ResponseShape.log(billing, kind: .grok, endpoint: "billing", keep: Self.logKeep)
        let decoded = try GrokBillingDecoding.decode(billing)
        return UsageSnapshot(
            accountID: AccountID(kind: .grok, remoteID: account),
            fetchedAt: Date(),
            plan: try await plan(credential, http),
            meters: decoded.meters,
            spend: decoded.spend,
            rawUnknownKeys: decoded.unknownKeys
        )
    }

    /// Rotates the refresh token; the caller persists the result.
    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        try await GrokDeviceAuth(http: http).refresh(credential)
    }

    /// Best effort: any failure but `.unauthorized` leaves the plan unknown.
    private func plan(_ c: Credential, _ http: HTTPClient) async throws -> String? {
        do {
            let (data, _) = try await http.send(Self.request(Self.settingsURL), bearer: c.access)
            ResponseShape.log(data, kind: .grok, endpoint: "settings", keep: Self.logKeep)
            return GrokBillingDecoding.plan(data)
        } catch ProviderError.unauthorized {
            throw ProviderError.unauthorized
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderError {
            Self.log.error("settings failed: \(error.description, privacy: .public)")
        } catch {
            Self.log.error("settings failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        return nil
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in clientHeaders { req.setValue(value, forHTTPHeaderField: name) }
        return req
    }
}
