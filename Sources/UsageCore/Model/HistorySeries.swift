import Foundation

/// History read-model values: GRDB-free so the app and widget can use them without linking UsageHistory.
public struct SeriesPoint: Equatable, Sendable {
    public var t: Date
    /// nil marks a gap (no data); charts break the line there.
    public var percent: Double?

    public init(t: Date, percent: Double?) {
        self.t = t
        self.percent = percent
    }
}

public struct Series: Equatable, Sendable {
    /// `meter@resets_at`: one id per reset window so step lines never join across resets.
    public var id: String
    public var meter: String
    public var points: [SeriesPoint]

    public init(id: String, meter: String, points: [SeriesPoint]) {
        self.id = id
        self.meter = meter
        self.points = points
    }
}

public struct RangeSummary: Equatable, Sendable {
    public var peakSession: Double?
    public var windowsOver90: Int
    public var weeklyAtEnd: Double?

    public init(peakSession: Double?, windowsOver90: Int, weeklyAtEnd: Double?) {
        self.peakSession = peakSession
        self.windowsOver90 = windowsOver90
        self.weeklyAtEnd = weeklyAtEnd
    }
}
