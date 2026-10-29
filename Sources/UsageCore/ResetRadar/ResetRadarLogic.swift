import Foundation

/// Pure decode / merge / notify-decision logic for the codex-reset.com timeline.
public enum ResetRadarLogic {
    /// Decodes `{"events": [...]}`. Events with an unknown `type` or missing `id`/`date` are skipped.
    public static func decode(_ data: Data) throws -> [ResetEvent] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let raw = obj["events"] as? [[String: Any]] else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        return raw.compactMap(event)
    }

    /// One event per `dedupeKey` (prefer confirmed, then latest `at`), sorted by `at` descending.
    public static func merged(_ events: [ResetEvent], limit: Int = 5) -> [ResetEvent] {
        var best: [String: ResetEvent] = [:]
        for e in events {
            guard let current = best[e.dedupeKey] else { best[e.dedupeKey] = e; continue }
            if rank(e) > rank(current) { best[e.dedupeKey] = e }
        }
        let sorted = best.values.sorted { a, b in
            let (x, y) = (a.at ?? .distantPast, b.at ?? .distantPast)
            return x != y ? x > y : a.day > b.day
        }
        return Array(sorted.prefix(limit))
    }

    /// Caption for the newest confirmed reset, or nil when there is none.
    public static func lastResetCaption(_ events: [ResetEvent], now: Date) -> String? {
        guard let at = events.filter({ $0.kind == .reset && $0.confirmed }).compactMap(\.at).max() else { return nil }
        let hours = Int(max(0, now.timeIntervalSince(at)) / 3600)
        if hours < 1 { return "Last reset just now" }
        if hours < 24 { return "Last reset \(hours)h ago" }
        return "Last reset \(hours / 24)d ago"
    }

    /// First run (`seen == nil`) seeds every confirmed key and notifies nothing. Otherwise notifies
    /// confirmed events with an unseen key (one per key; credits only when `includeCredits`) and
    /// records every confirmed key, notified or not.
    public static func pending(_ events: [ResetEvent], seen: Set<String>?, includeCredits: Bool) -> (notify: [ResetEvent], seen: Set<String>) {
        let confirmed = events.filter(\.confirmed)
        let allKeys = Set(confirmed.map(\.dedupeKey))
        guard let seen else { return ([], allKeys) }
        var notified = Set<String>()
        let notify = confirmed.filter { e in
            guard !seen.contains(e.dedupeKey), includeCredits || e.kind != .credits else { return false }
            return notified.insert(e.dedupeKey).inserted
        }
        return (notify, seen.union(allKeys))
    }

    // MARK: - Private

    private static func rank(_ e: ResetEvent) -> (Int, Date) {
        (e.confirmed ? 1 : 0, e.at ?? .distantPast)
    }

    private static func event(_ o: [String: Any]) -> ResetEvent? {
        guard let id = o["id"] as? String,
              let day = o["date"] as? String,
              let kind = (o["type"] as? String).flatMap(ResetEvent.Kind.init(rawValue:)) else { return nil }
        return ResetEvent(
            id: id,
            day: day,
            kind: kind,
            summary: cleanSummary(o["summary"] as? String ?? ""),
            url: (o["url"] as? String).flatMap(URL.init(string:)),
            at: date(o["announced_at"]) ?? date(o["observed_at"]),
            confirmed: o["confirmed"] as? Bool ?? false
        )
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static let entities: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    static func cleanSummary(_ s: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let tail = rest[rest.index(after: amp)...]
            if let semi = tail.prefix(10).firstIndex(of: ";"), let ch = entity(tail[..<semi]) {
                out += ch
                rest = tail[tail.index(after: semi)...]
            } else {
                out += "&"
                rest = tail
            }
        }
        out += rest
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func entity(_ name: Substring) -> String? {
        if let named = entities[String(name)] { return named }
        guard name.first == "#" else { return nil }
        let digits = name.dropFirst()
        let code = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
