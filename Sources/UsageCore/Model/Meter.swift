import Foundation

public struct Meter: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case session5h, weeklyAll, weeklyModel, copilotPremium, copilotChat, copilotCompletions
    }

    public enum Severity: String, Codable, Sendable { case normal, warning, critical }

    public var kind: Kind
    public var label: String
    public var percentUsed: Double?
    public var used: Double?
    public var limit: Double?
    public var unit: String?
    public var resetsAt: Date?
    public var windowLength: Duration?
    public var isUnlimited: Bool
    public var severity: Severity

    public init(
        kind: Kind,
        label: String,
        percentUsed: Double?,
        used: Double? = nil,
        limit: Double? = nil,
        unit: String? = nil,
        resetsAt: Date? = nil,
        windowLength: Duration? = nil,
        isUnlimited: Bool = false,
        severity: Severity = .normal
    ) {
        self.kind = kind
        self.label = label
        self.percentUsed = percentUsed
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
        self.windowLength = windowLength
        self.isUnlimited = isUnlimited
        self.severity = severity
    }

    /// Elapsed fraction of the window: `1 - (resetsAt - now) / windowLength`, clamped to 0...1.
    public func paceFraction(now: Date) -> Double? {
        guard let resetsAt, let windowLength else { return nil }
        let window = Double(windowLength.components.seconds) + Double(windowLength.components.attoseconds) / 1e18
        guard window > 0 else { return nil }
        return min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / window))
    }

    public func isAheadOfPace(now: Date) -> Bool {
        guard let percentUsed, let pace = paceFraction(now: now) else { return false }
        return percentUsed / 100 > pace
    }

    public func displaySeverity(now: Date) -> Severity {
        if let percentUsed, percentUsed >= 90 { return .critical }
        if let percentUsed, percentUsed >= 75 { return .warning }
        if isAheadOfPace(now: now) { return .warning }
        return severity
    }
}
