import Foundation

/// GitHub Copilot usage from `GET /copilot_internal/user`, authenticated with a token borrowed from gh.
public struct CopilotProvider: UsageProvider {
    public static let userURL = URL(string: "https://api.github.com/copilot_internal/user")!
    /// Premium usage is billed in AI credits; 1 credit ≈ $0.01, so a credit count is a USD minor amount.
    static let creditCurrency = "USD"

    public let kind: ProviderKind = .copilot
    public let minimumInterval: Duration = .seconds(60)

    public init() {}

    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.userURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await http.send(req, bearer: credential.access)
        // The account id is assigned by the caller; a placeholder keeps decoding pure.
        return try Self.decode(data, accountID: AccountID(kind: .copilot, remoteID: "unknown"), now: Date())
    }

    /// Copilot tokens are re-read from gh, never refreshed here.
    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }

    public static func decode(_ data: Data, accountID: AccountID, now: Date) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let quotas = root["quota_snapshots"] as? [String: Any],
              let premium = quotas["premium_interactions"] as? [String: Any] else {
            throw ProviderError.schema(keys: root.keys.sorted())
        }
        let reset = ClaudeProvider.date(root["quota_reset_date_utc"]) ?? day(root["quota_reset_date"])
        var meters = [premiumMeter(premium, reset: reset)]
        for (key, kind, label) in [
            ("chat", Meter.Kind.copilotChat, "Chat"),
            ("completions", Meter.Kind.copilotCompletions, "Completions"),
        ] {
            if let q = quotas[key] as? [String: Any], let m = countMeter(q, kind: kind, label: label, reset: reset) {
                meters.append(m)
            }
        }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: now,
            plan: planName(root["copilot_plan"] as? String),
            meters: meters,
            spend: overage(premium)
        )
    }

    /// Premium meter. Entitlement 0 keeps `limit = 0` and no percent, which the UI shows as "Not included".
    private static func premiumMeter(_ q: [String: Any], reset: Date?) -> Meter {
        if q["unlimited"] as? Bool == true {
            return Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: nil, unit: "credits", resetsAt: reset, isUnlimited: true)
        }
        let entitlement = ClaudeProvider.number(q["entitlement"]) ?? 0
        let remaining = ClaudeProvider.number(q["remaining"]) ?? 0
        guard entitlement > 0 else {
            return Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: nil, used: 0, limit: 0, unit: "credits", resetsAt: reset)
        }
        let percent = ClaudeProvider.number(q["percent_remaining"]).map { ((100 - $0) * 10).rounded() / 10 }
        return Meter(
            kind: .copilotPremium,
            label: "Premium requests",
            percentUsed: percent,
            used: entitlement - remaining,
            limit: entitlement,
            unit: "credits",
            resetsAt: reset
        )
    }

    /// Chat / completions: dropped when unlimited or not included.
    private static func countMeter(_ q: [String: Any], kind: Meter.Kind, label: String, reset: Date?) -> Meter? {
        guard q["unlimited"] as? Bool != true,
              let entitlement = ClaudeProvider.number(q["entitlement"]), entitlement > 0 else { return nil }
        let remaining = ClaudeProvider.number(q["remaining"]) ?? entitlement
        return Meter(
            kind: kind,
            label: label,
            percentUsed: (entitlement - remaining) / entitlement * 100,
            used: entitlement - remaining,
            limit: entitlement,
            resetsAt: reset
        )
    }

    /// Overage credits beyond the entitlement, as USD cents (1 credit ≈ $0.01).
    private static func overage(_ q: [String: Any]) -> Money? {
        guard q["overage_permitted"] as? Bool == true,
              let count = ClaudeProvider.number(q["overage_count"]), count > 0 else { return nil }
        return Money(usedMinor: Int(count.rounded()), limitMinor: nil, currency: creditCurrency, exponent: 2)
    }

    static func planName(_ raw: String?) -> String? {
        switch raw {
        case nil: nil
        case "enterprise": "Enterprise"
        case "individual": "Pro"
        case "free": "Free"
        case let other?: other
        }
    }

    private static func day(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: s)
    }
}
