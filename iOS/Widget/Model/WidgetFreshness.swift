import Foundation
import UsageCore

enum WidgetFreshness {
    enum Freshness: Equatable, Sendable { case fresh, stale, failed(AccountStatus), noData }

    static let expectedRefresh: TimeInterval = 900
    /// 2x expected refresh.
    static let staleAfter: TimeInterval = 1800

    /// No snapshot, then hard failure, then age. Rate limited / offline with a young snapshot stay fresh.
    static func freshness(fetchedAt: Date?, status: AccountStatus?, at: Date) -> Freshness {
        guard let fetchedAt else { return .noData }
        switch status {
        case .needsLogin?, .codexNotSignedIn?, .schemaError?: return .failed(status!)
        default: break
        }
        return at.timeIntervalSince(fetchedAt) > staleAfter ? .stale : .fresh
    }

    static func ageText(fetchedAt: Date, at: Date, calendar: Calendar, settings: DisplaySettings) -> String {
        MeterDisplay.ageShort(fetchedAt: fetchedAt, now: at, options: settings.meterOptions(calendar: calendar))
    }
}
