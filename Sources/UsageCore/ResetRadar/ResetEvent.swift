import Foundation

/// One entry of the codex-reset.com timeline.
public struct ResetEvent: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case reset, credits }

    public let id: String
    /// API `date`, e.g. "2026-10-28".
    public let day: String
    public let kind: Kind
    /// HTML entities decoded, whitespace collapsed.
    public let summary: String
    public let url: URL?
    /// `announced_at ?? observed_at`.
    public let at: Date?
    public let confirmed: Bool

    public var dedupeKey: String { "\(kind.rawValue)|\(day)" }

    public init(id: String, day: String, kind: Kind, summary: String, url: URL?, at: Date?, confirmed: Bool) {
        self.id = id
        self.day = day
        self.kind = kind
        self.summary = summary
        self.url = url
        self.at = at
        self.confirmed = confirmed
    }
}
