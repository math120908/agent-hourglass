import Foundation

extension ClaudeProvider {
    /// Top-level keys the decoder understands; everything else lands in `rawUnknownKeys`.
    static let knownKeys: Set<String> = ["limits", "spend", "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "extra_usage"]

    public static func decodeUsage(_ data: Data, accountID: AccountID, now: Date) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        let unknown = root.keys.filter { !knownKeys.contains($0) }.sorted()
        var meters = (root["limits"] as? [[String: Any]]).map(metersFromLimits) ?? []
        if meters.isEmpty { meters = legacyMeters(root) }
        guard !meters.isEmpty else { throw ProviderError.schema(keys: root.keys.sorted()) }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: now,
            meters: meters,
            spend: (root["spend"] as? [String: Any]).flatMap(decodeSpend),
            rawUnknownKeys: unknown
        )
    }

    private static func metersFromLimits(_ limits: [[String: Any]]) -> [Meter] {
        limits.compactMap { l in
            let percent = number(l["percent"])
            let reset = date(l["resets_at"])
            switch l["kind"] as? String {
            case "session":
                return Meter(kind: .session5h, label: "Session", percentUsed: percent, resetsAt: reset, windowLength: .seconds(5 * 3600))
            case "weekly_all":
                return Meter(kind: .weeklyAll, label: "All models", percentUsed: percent, resetsAt: reset, windowLength: .seconds(7 * 86400))
            case "weekly_scoped":
                let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                return Meter(kind: .weeklyModel, label: model ?? "Model", percentUsed: percent, resetsAt: reset, windowLength: .seconds(7 * 86400))
            default:
                return nil
            }
        }
    }

    private static func legacyMeters(_ root: [String: Any]) -> [Meter] {
        var out: [Meter] = []
        if let s = root["five_hour"] as? [String: Any], let p = number(s["utilization"]) {
            out.append(Meter(kind: .session5h, label: "Session", percentUsed: p, resetsAt: date(s["resets_at"]), windowLength: .seconds(5 * 3600)))
        }
        if let w = root["seven_day"] as? [String: Any], let p = number(w["utilization"]) {
            out.append(Meter(kind: .weeklyAll, label: "All models", percentUsed: p, resetsAt: date(w["resets_at"]), windowLength: .seconds(7 * 86400)))
        }
        return out
    }

    private static func decodeSpend(_ s: [String: Any]) -> Money? {
        guard let used = s["used"] as? [String: Any],
              let usedMinor = number(used["amount_minor"]),
              let currency = used["currency"] as? String else { return nil }
        let limitMinor = ((s["limit"] as? [String: Any]).flatMap { number($0["amount_minor"]) }).map { Int($0) }
        return Money(
            usedMinor: Int(usedMinor),
            limitMinor: limitMinor,
            currency: currency,
            exponent: Int(number(used["exponent"]) ?? 2),
            isEnabled: number(s["enabled"]).map { $0 != 0 } ?? true,
            disabledReason: s["disabled_reason"] as? String
        )
    }

    static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    public static func decodeTokenResponse(_ data: Data, now: Date) throws -> (Credential, remoteAccountID: String, email: String?) {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let access = j["access_token"] as? String,
              let account = j["account"] as? [String: Any],
              let id = account["uuid"] as? String else {
            throw ProviderError.schema(keys: j.keys.sorted())
        }
        let scopes = (j["scope"] as? String)?.split(separator: " ").map(String.init) ?? [ClaudeOAuth.scope]
        let cred = Credential(
            kind: .claude,
            access: Secret(access),
            refresh: (j["refresh_token"] as? String).map(Secret.init),
            expiresAt: number(j["expires_in"]).map { now.addingTimeInterval($0) },
            refreshExpiresAt: number(j["refresh_token_expires_in"]).map { now.addingTimeInterval($0) },
            scopes: scopes,
            accountEmail: account["email_address"] as? String
        )
        return (cred, id, cred.accountEmail)
    }
}
