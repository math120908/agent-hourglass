import Foundation

/// Header and footer strings for the Instrument History window.
public struct HistorySummaryFormatting: Equatable, Sendable {
    public var weeklyNow: String
    public var peakSession: String
    public var windowsHit90: String

    public init(summary: RangeSummary?, isEmpty: Bool) {
        self.init(peak: summary?.peakSession, windows: summary?.windowsOver90 ?? 0, weekly: summary?.weeklyAtEnd, isEmpty: isEmpty)
    }

    public init(peak: Double?, windows n: Int, weekly: Double?, isEmpty: Bool) {
        func pct(_ v: Double?) -> String { isEmpty ? "--" : v.map { "\(Int($0.rounded()))%" } ?? "--" }
        weeklyNow = pct(weekly)
        peakSession = pct(peak)
        windowsHit90 = isEmpty ? "No data" : "\(n) \(n == 1 ? "window" : "windows") hit 90%"
    }

    /// "Oct 19 14:42 to Now", or with an explicit end when stepped back.
    public static func rangeLabel(_ iv: DateInterval, isNow: Bool, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "MMM d HH:mm"
        return "\(f.string(from: iv.start)) to \(isNow ? "Now" : f.string(from: iv.end))"
    }
}
