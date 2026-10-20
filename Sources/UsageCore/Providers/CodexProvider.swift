import Foundation

/// OpenAI Codex (ChatGPT plan) usage from `GET chatgpt.com/backend-api/wham/usage` (R5).
/// The token is borrowed read-only from the Codex CLI; the `credential` argument is ignored.
public struct CodexProvider: UsageProvider {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let knownKeys: Set<String> = [
        "user_id", "account_id", "email", "plan_type", "rate_limit", "credits", "spend_control", "additional_rate_limits",
    ]

    public let kind: ProviderKind = .codex
    /// R5 politeness: one request per account per 5 min at most.
    public let minimumInterval: Duration = .seconds(300)
    public let auth: CodexAuthSource

    public init(auth: CodexAuthSource) { self.auth = auth }

    /// Placeholder handed to `fetch`; Codex never keeps a credential of its own.
    static let borrowed = Credential(kind: .codex, access: Secret(""), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])

    /// 401 drops the cached token, re-reads auth.json once and retries once; a second 401 is `invalidGrant`.
    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        do {
            return try await fetchOnce(http)
        } catch ProviderError.unauthorized {
            auth.invalidate()
            do {
                return try await fetchOnce(http)
            } catch ProviderError.unauthorized {
                throw ProviderError.invalidGrant
            }
        }
    }

    private func fetchOnce(_ http: HTTPClient) async throws -> UsageSnapshot {
        let login = try auth.login()
        var req = URLRequest(url: Self.usageURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(login.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        let (data, _) = try await http.send(req, bearer: login.access)
        return try Self.decode(data, accountID: AccountID(kind: .codex, remoteID: login.accountID), now: Date())
    }

    /// Never refreshes: rotating the CLI's refresh token would log the CLI out.
    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }

    public static func decode(_ data: Data, accountID: AccountID, now: Date) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let limit = root["rate_limit"] as? [String: Any] else { throw ProviderError.schema(keys: root.keys.sorted()) }
        var meters = windows(limit, name: nil)
        for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let rl = extra["rate_limit"] as? [String: Any] else { continue }
            let name = (extra["limit_name"] ?? extra["metered_feature"]) as? String
            meters += windows(rl, name: name ?? "Additional")
        }
        guard !meters.isEmpty else { throw ProviderError.schema(keys: root.keys.sorted()) }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: now,
            plan: root["plan_type"] as? String,
            meters: meters,
            spend: (root["credits"] as? [String: Any]).flatMap(credits),
            rawUnknownKeys: root.keys.filter { !knownKeys.contains($0) }.sorted()
        )
    }

    private static func windows(_ rl: [String: Any], name: String?) -> [Meter] {
        ["primary_window", "secondary_window"].compactMap { key in
            guard let w = rl[key] as? [String: Any],
                  let seconds = ClaudeProvider.number(w["limit_window_seconds"]).map({ Int($0) }), seconds > 0 else { return nil }
            let label = Meter.windowLabel(seconds: seconds)
            return Meter(
                kind: .window,
                label: name.map { "\($0), \(label.lowercased())" } ?? label,
                percentUsed: ClaudeProvider.number(w["used_percent"]),
                resetsAt: ClaudeProvider.number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) },
                windowLength: .seconds(seconds),
                severity: rl["limit_reached"] as? Bool == true ? .critical : .normal
            )
        }
    }

    /// Credit balance as a count (no currency). Unlimited or no credits: no spend line.
    private static func credits(_ c: [String: Any]) -> Money? {
        guard c["has_credits"] as? Bool == true, c["unlimited"] as? Bool != true else { return nil }
        let raw = ClaudeProvider.number(c["balance"]) ?? (c["balance"] as? String).flatMap(Double.init)
        guard let balance = raw else { return nil }
        return Money(usedMinor: Int(balance.rounded()), limitMinor: nil, currency: "credits", exponent: 0)
    }
}
