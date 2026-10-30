import Foundation

/// Tier, plan and project from `v1internal:loadCodeAssist` (R9 §2). Every field optional.
public struct CodeAssistInfo: Equatable, Sendable {
    public var tierID: String?
    public var tierName: String?
    public var planLabel: String?
    public var project: String?
    public var ineligibleReasons: [String]
    public var unknownKeys: [String]
}

/// Tolerant decoding of the Google Code Assist responses (R9 §2, CodexBar `AntigravityQuotaSummaryParser.swift`).
enum GoogleQuotaDecoding {
    static let codeAssistKeys: Set<String> = [
        "currentTier", "paidTier", "cloudaicompanionProject", "allowedTiers", "ineligibleTiers", "planInfo",
    ]

    static func codeAssist(_ data: Data) throws -> CodeAssistInfo {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        let current = root["currentTier"] as? [String: Any]
        let paid = root["paidTier"] as? [String: Any]
        let project = root["cloudaicompanionProject"]
        return CodeAssistInfo(
            tierID: nonEmpty(current?["id"]),
            tierName: nonEmpty(current?["name"]),
            planLabel: nonEmpty(paid?["name"]) ?? nonEmpty(current?["name"]),
            project: nonEmpty(project) ?? nonEmpty((project as? [String: Any])?["id"]),
            ineligibleReasons: (root["ineligibleTiers"] as? [[String: Any]] ?? []).compactMap { nonEmpty($0["reasonCode"]) },
            unknownKeys: root.keys.filter { !codeAssistKeys.contains($0) }.sorted()
        )
    }

    /// One `.window` meter per enabled bucket of `retrieveUserQuotaSummary`, in payload order.
    static func summaryMeters(_ data: Data) throws -> [Meter] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        // CodexBar also accepts the summary wrapped in `response` or `summary`.
        let payload = root["groups"] != nil ? root : (root["response"] ?? root["summary"]) as? [String: Any]
        guard let groups = payload?["groups"] as? [[String: Any]] else { throw ProviderError.schema(keys: root.keys.sorted()) }
        let meters = groups.flatMap(groupMeters)
        guard !meters.isEmpty else { throw ProviderError.schema(keys: root.keys.sorted()) }
        return meters
    }

    /// Window length derived from `window`, else `bucketId` (the payload carries no number).
    static func windowSeconds(bucketID: String?, window: String?) -> Int? {
        func match(_ raw: String?) -> Int? {
            guard let s = raw?.lowercased() else { return nil }
            if s.contains("5h") { return 18000 }
            if s.contains("week") { return 604_800 }
            if s.contains("daily") || s.contains("24h") { return 86400 }
            return nil
        }
        return match(window) ?? match(bucketID)
    }

    private static func groupMeters(_ group: [String: Any]) -> [Meter] {
        let display = nonEmpty(group["displayName"]) ?? nonEmpty(group["name"])
        let name: String
        let pool: String
        if display?.contains("Gemini") == true {
            (name, pool) = ("Gemini", "gemini")
        } else if display?.contains("Claude") == true || display?.contains("GPT") == true {
            (name, pool) = ("Claude + GPT", "claude-gpt")
        } else {
            (name, pool) = (display ?? "Quota", (display ?? "quota").lowercased())
        }
        return (group["buckets"] as? [[String: Any]] ?? []).compactMap { bucket in
            guard bucket["disabled"] as? Bool != true else { return nil }
            let id = nonEmpty(bucket["bucketId"]) ?? nonEmpty(bucket["id"])
            let bucketName = nonEmpty(bucket["displayName"]) ?? nonEmpty(bucket["name"])
            let seconds = windowSeconds(bucketID: id, window: nonEmpty(bucket["window"]))
            let fraction = CodexDeviceAuth.number(bucket["remainingFraction"]) ?? remaining(bucket["remaining"])
            return Meter(
                kind: .window,
                label: "\(name), \(seconds.map { Meter.windowLabel(seconds: $0).lowercased() } ?? bucketName ?? id ?? "quota")",
                percentUsed: fraction.map { min(100, max(0, (1 - $0) * 100)) },
                resetsAt: CodexDeviceAuth.date(bucket["resetTime"]),
                windowLength: seconds.map { .seconds($0) },
                pool: seconds == nil ? "\(pool).\(id ?? bucketName ?? "quota")" : pool
            )
        }
    }

    /// `remaining.remainingFraction`, or the ProtoJSON oneof form `{"case": "remainingFraction", "value": x}`.
    private static func remaining(_ raw: Any?) -> Double? {
        guard let r = raw as? [String: Any] else { return nil }
        if let f = CodexDeviceAuth.number(r["remainingFraction"]) { return f }
        return r["case"] as? String == "remainingFraction" ? CodexDeviceAuth.number(r["value"]) : nil
    }

    private static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
