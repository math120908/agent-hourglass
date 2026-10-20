import Foundation
import UsageCore

/// One account as the popover sees it.
struct PopoverAccount: Identifiable {
    var id: AccountID
    var name: String
    var kind: ProviderKind
    var snapshot: UsageSnapshot?
    var status: AccountStatus

    func card(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> CardModel {
        CardModel.make(snapshot: snapshot, status: status, kind: kind, now: now, calendar: calendar, locale: locale)
    }
}

/// Everything the popover renders, independent of where it came from (live AppState or fixture).
struct PopoverContent {
    var accounts: [PopoverAccount]
    var isOffline: Bool
    var now: Date
    var calendar: Calendar = .current

    @MainActor
    static func live(_ state: AppState, now: Date = Date()) -> PopoverContent {
        let accounts = state.accounts.map { id in
            PopoverAccount(
                id: id,
                name: id.rawValue.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id.rawValue,
                kind: id.kind ?? .claude,
                snapshot: state.snapshots[id],
                status: state.statuses[id] ?? .noData
            )
        }
        return PopoverContent(accounts: accounts, isOffline: state.isOffline, now: now)
    }

    var attentionCount: Int {
        accounts.filter { !($0.status == .fresh || $0.status == .noData) }.count
    }

    var lastUpdated: Date? { accounts.compactMap { $0.snapshot?.fetchedAt }.max() }

    var statusLine: String {
        if isOffline { return "Offline" }
        let n = attentionCount
        if n > 0 { return n == 1 ? "1 account needs attention" : "\(n) accounts need attention" }
        guard let at = lastUpdated else { return "No data yet" }
        return "All accounts updated \(clock(at))"
    }

    func clock(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
