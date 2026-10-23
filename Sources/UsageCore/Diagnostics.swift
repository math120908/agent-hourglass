import CryptoKit
import Foundation

/// Redacted diagnostics for "Copy diagnostics" (spec §10.5): ids hashed, no names, logins or tokens.
public enum Diagnostics {
    public struct Account: Sendable {
        public var id: AccountID
        public var kind: ProviderKind
        public var status: AccountStatus
        public var snapshot: UsageSnapshot?

        public init(id: AccountID, kind: ProviderKind, status: AccountStatus, snapshot: UsageSnapshot?) {
            self.id = id
            self.kind = kind
            self.status = status
            self.snapshot = snapshot
        }
    }

    /// First 8 hex chars of SHA-256 over the raw id.
    public static func hash(_ id: AccountID) -> String {
        SHA256.hash(data: Data(id.rawValue.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    public static func report(app: String, accounts: [Account], isOffline: Bool, interval: Duration, now: Date) -> String {
        var lines = [
            "app: \(app)",
            "os: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "generated: \(ISO8601DateFormatter().string(from: now))",
            "offline: \(isOffline)",
            "interval: \(interval.components.seconds)s",
            "accounts: \(accounts.count)",
        ]
        for a in accounts {
            var line = "- \(a.kind.rawValue) \(hash(a.id)) status=\(statusName(a.status))"
            if let s = a.snapshot {
                line += " meters=\(s.meters.count) age=\(Int(now.timeIntervalSince(s.fetchedAt)))s"
                line += " unknownKeys=[\(s.rawUnknownKeys.sorted().joined(separator: ","))]"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    public static func statusName(_ s: AccountStatus) -> String {
        switch s {
        case .fresh: "fresh"
        case .stale: "stale"
        case .rateLimited: "rateLimited"
        case .offline: "offline"
        case .needsLogin: "needsLogin"
        case .ghMissing: "ghMissing"
        case .ghLoginRemoved: "ghLoginRemoved"
        case .schemaError: "schemaError"
        case .noData: "noData"
        case .codexNotSignedIn: "codexNotSignedIn"
        case .claudeCodeNotSignedIn: "claudeCodeNotSignedIn"
        case .claudeCodeExpired: "claudeCodeExpired"
        case .claudeCodeDenied: "claudeCodeDenied"
        }
    }
}
