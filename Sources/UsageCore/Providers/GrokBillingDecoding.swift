import Foundation

/// Tolerant decoding of the Grok CLI-proxy `/v1/billing?format=credits` and `/v1/settings` responses
/// (R10 §2a, ClaudeBar `docs/providers/grok/design.md`). Every field optional.
enum GrokBillingDecoding {
    static let knownKeys: Set<String> = [
        "currentPeriod", "creditUsagePercent", "onDemandCap", "onDemandUsed", "productUsage", "prepaidBalance",
        "billingPeriodStart", "billingPeriodEnd",
    ]

    /// Main pool meter first, then one meter per product in payload order. The main meter has no pool;
    /// each product meter's pool is its name lowercased, so same-window keys stay apart.
    static func decode(_ data: Data) throws -> (meters: [Meter], spend: Money?, unknownKeys: [String]) {
        guard let outer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        let wrapped = outer["config"] as? [String: Any]
        let root = wrapped ?? outer
        let period = root["currentPeriod"] as? [String: Any]
        let percent = finite(root["creditUsagePercent"])
        let products: [(name: String, percent: Double?)] = (root["productUsage"] as? [Any] ?? []).compactMap { raw in
            guard let p = raw as? [String: Any], let name = productName(p["product"]) else { return nil }
            return (name, finite(p["usagePercent"]))
        }
        guard period != nil || percent != nil || !products.isEmpty else { throw ProviderError.schema(keys: outer.keys.sorted()) }

        let resetsAt = CodexDeviceAuth.date(period?["end"]) ?? CodexDeviceAuth.date(root["billingPeriodEnd"])
        let start = CodexDeviceAuth.date(period?["start"]) ?? CodexDeviceAuth.date(root["billingPeriodStart"])
        let seconds = windowSeconds(type: period?["type"] as? String, start: start, end: resetsAt)
        let label = seconds.map(Meter.windowLabel(seconds:)) ?? "Usage"
        let window = seconds.map { Duration.seconds($0) }

        var meters = [Meter(kind: .window, label: label, percentUsed: percent, resetsAt: resetsAt, windowLength: window)]
        meters += products.map {
            Meter(
                kind: .window,
                label: "\($0.name), \(label.lowercased())",
                percentUsed: $0.percent,
                resetsAt: resetsAt,
                windowLength: window,
                pool: $0.name.lowercased()
            )
        }
        var unknown = root.keys.filter { !knownKeys.contains($0) }
        if wrapped != nil { unknown += outer.keys.filter { $0 != "config" } }
        return (meters, spend(root), unknown.sorted())
    }

    /// `subscription_tier_display` from `/v1/settings`, e.g. "SuperGrok".
    static func plan(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tier = root["subscription_tier_display"] as? String, !tier.isEmpty else { return nil }
        return tier
    }

    /// WEEKLY / DAILY by period type, else `end - start` when both parse.
    private static func windowSeconds(type: String?, start: Date?, end: Date?) -> Int? {
        if let type, type.contains("WEEKLY") { return 604_800 }
        if let type, type.contains("DAILY") { return 86400 }
        guard let start, let end else { return nil }
        let s = Int(end.timeIntervalSince(start).rounded())
        return s > 0 ? s : nil
    }

    /// On-demand usage against its cap (USD cents), else none. A prepaid balance is credit left, not spend.
    private static func spend(_ root: [String: Any]) -> Money? {
        guard let cap = cents(root["onDemandCap"]), cap > 0 else { return nil }
        return Money(usedMinor: cents(root["onDemandUsed"]) ?? 0, limitMinor: cap, currency: "USD", exponent: 2)
    }

    private static func cents(_ raw: Any?) -> Int? {
        finite((raw as? [String: Any])?["val"]).flatMap { Int(exactly: $0.rounded()) }
    }

    /// A non-finite number ("NaN", "Infinity") is unknown, never 0.
    private static func finite(_ raw: Any?) -> Double? {
        guard let n = CodexDeviceAuth.number(raw), n.isFinite else { return nil }
        return n
    }

    /// "GrokBuild" → "Build"; a bare "Grok" stays as is.
    private static func productName(_ raw: Any?) -> String? {
        guard let name = raw as? String, !name.isEmpty else { return nil }
        let trimmed = name.hasPrefix("Grok") ? String(name.dropFirst(4)) : name
        return trimmed.isEmpty ? name : trimmed
    }
}
