import Foundation
import os

/// Google AI plan quota from the Code Assist `v1internal` API, signed in as the Antigravity client (R9 §2).
/// Order: loadCodeAssist → retrieveUserQuotaSummary, falling back to fetchAvailableModels and
/// retrieveUserQuota. A placeholder is never shown as real quota (decision 6).
public struct GoogleProvider: UsageProvider {
    public static let hubUserAgent = "antigravity/hub/2.9.1 darwin/arm64"
    public static let metadata: [String: String] = ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
    public static let prodBase = URL(string: "https://cloudcode-pa.googleapis.com/v1internal")!
    public static let dailyBase = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal")!
    /// Ineligible reasons that mean this client may not sign in at all: the user signs in again.
    static let loginReasons: Set<String> = ["GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT", "UNSUPPORTED_CLIENT"]
    /// String keys whose values survive in the shape log. No identity, project or numeric-id field.
    static let shapeKeep: Set<String> = [
        "bucketId", "window", "displayName", "reasonCode", "tierId", "id", "name", "modelId", "resetTime", "planType", "type", "disabled",
    ]

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "GoogleProvider")

    public let kind: ProviderKind = .google
    /// R9 politeness: one request round per account per 5 min at most.
    public let minimumInterval: Duration = .seconds(300)
    private let client: any GoogleOAuthClientSource

    public init(client: any GoogleOAuthClientSource) { self.client = client }

    /// `.unauthorized` from any step propagates so `AccountClient` refreshes and retries once.
    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        guard let remote = credential.remoteAccountID, !remote.isEmpty else { throw ProviderError.invalidGrant }
        let bearer = credential.access
        let info = try GoogleQuotaDecoding.codeAssist(
            try await post(Self.prodBase, "loadCodeAssist", ["metadata": Self.metadata], bearer, http)
        )
        guard let project = info.project else {
            if let reason = info.ineligibleReasons.first(where: Self.loginReasons.contains) {
                Self.log.error("loadCodeAssist: ineligible \(reason, privacy: .public)")
                throw ProviderError.invalidGrant
            }
            Self.log.info("loadCodeAssist: no project")
            throw QuotaError.unavailable
        }
        let meters = try await quotaMeters(project: project, bearer: bearer, http: http)
        return UsageSnapshot(
            accountID: AccountID(kind: .google, remoteID: remote),
            fetchedAt: Date(),
            plan: info.planLabel,
            meters: meters,
            rawUnknownKeys: info.unknownKeys
        )
    }

    /// The summary is trusted once eligibility passed. The fallbacks count only when confirmed.
    private func quotaMeters(project: String, bearer: Secret, http: HTTPClient) async throws -> [Meter] {
        let body = ["project": project]
        do {
            return try GoogleQuotaDecoding.summaryMeters(try await post(Self.dailyBase, "retrieveUserQuotaSummary", body, bearer, http))
        } catch let error as ProviderError where Self.fallsBack(error) {
            Self.log.info("retrieveUserQuotaSummary: \(error.description, privacy: .public), trying fetchAvailableModels")
        }
        let models: [Meter]
        do {
            models = try GoogleQuotaDecoding.modelMeters(try await post(Self.prodBase, "fetchAvailableModels", body, bearer, http))
        } catch let error as ProviderError where Self.fallsBack(error) {
            Self.log.info("fetchAvailableModels: \(error.description, privacy: .public), trying retrieveUserQuota")
            guard let fractions = try await confirmation(body, bearer, http), !fractions.isEmpty else { throw QuotaError.unavailable }
            return fractions.keys.sorted().map { id in
                Meter(kind: .window, label: id, percentUsed: GoogleQuotaDecoding.percentUsed(remaining: fractions[id]), pool: id)
            }
        }
        guard GoogleQuotaDecoding.isUnconfirmedPlaceholder(models: models, confirmed: nil) else { return models }
        let confirmed = try await confirmation(body, bearer, http)
        guard !GoogleQuotaDecoding.isUnconfirmedPlaceholder(models: models, confirmed: confirmed) else {
            Self.log.info("fetchAvailableModels: unconfirmed placeholder")
            throw QuotaError.unavailable
        }
        return models
    }

    /// `retrieveUserQuota` fractions, or nil when the call fails. Unauthorized, rate-limited and
    /// offline still propagate: they are not a verdict on the quota.
    private func confirmation(_ body: [String: String], _ bearer: Secret, _ http: HTTPClient) async throws -> [String: Double]? {
        do {
            return try GoogleQuotaDecoding.quotaFractions(try await post(Self.prodBase, "retrieveUserQuota", body, bearer, http))
        } catch let error as ProviderError {
            switch error {
            case .unauthorized, .rateLimited, .transport: throw error
            default:
                Self.log.info("retrieveUserQuota: \(error.description, privacy: .public)")
                return nil
            }
        }
    }

    private static func fallsBack(_ error: ProviderError) -> Bool {
        switch error {
        case let .http(status, _, _): status == 403 || status == 404
        case .schema: true
        default: false
        }
    }

    private func post(_ base: URL, _ method: StaticString, _ body: [String: Any], _ bearer: Secret, _ http: HTTPClient) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(base.absoluteString):\(method)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.hubUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, _) = try await http.send(req, bearer: bearer)
        ResponseShape.log(data, kind: .google, endpoint: method, keep: Self.shapeKeep)
        return data
    }

    /// Google does not rotate refresh tokens. A rejected client secret is dropped from the cache.
    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        do {
            return try await GoogleOAuth(http: http).refresh(credential, client: try await client.client())
        } catch GoogleOAuthError.clientRejected {
            await client.invalidate()
            throw GoogleOAuthError.clientUnavailable
        }
    }
}
