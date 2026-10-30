import Foundation
import os

/// Redacted outline of a provider response for debug logs: structure, numbers, bools and
/// nulls survive; strings become `<str N>` unless their key is kept; sensitive keys are
/// always `<redacted>`. Raw response logging goes only through here.
public enum ResponseShape {
    private static let logger = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "ResponseShape")
    private static let arrayLimit = 20
    private static let sensitiveParts = ["token", "secret", "password", "cookie", "email", "project", "authorization"]
    private static let sensitiveNames: Set<String> = ["sub", "code", "device_code", "user_code", "key"]

    public static func describe(_ data: Data, keep: Set<String> = []) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return "<non-json \(data.count) bytes>"
        }
        let shaped = redact(root, keep: keep, kept: false)
        guard let out = try? JSONSerialization.data(withJSONObject: shaped, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else {
            return "<non-json \(data.count) bytes>"
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func log(_ data: Data, kind: ProviderKind, endpoint: StaticString, keep: Set<String>) {
        let provider = kind.rawValue
        let shape = describe(data, keep: keep)
        logger.debug("\(provider, privacy: .public) \(endpoint, privacy: .public) \(shape, privacy: .public)")
    }

    static func isSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        return sensitiveNames.contains(k) || sensitiveParts.contains { k.contains($0) }
    }

    /// `kept`: the nearest enclosing key is in `keep`, so a string here survives.
    private static func redact(_ value: Any, keep: Set<String>, kept: Bool) -> Any {
        switch value {
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (key, child) in dict {
                out[key] = isSensitive(key) ? "<redacted>" : redact(child, keep: keep, kept: keep.contains(key))
            }
            return out
        case let array as [Any]:
            var out = array.prefix(arrayLimit).map { redact($0, keep: keep, kept: kept) }
            if array.count > arrayLimit { out.append("…+\(array.count - arrayLimit)") }
            return out
        case let s as String:
            return kept ? s : "<str \(s.count)>"
        default:
            return value
        }
    }
}
