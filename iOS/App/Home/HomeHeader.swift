import SwiftUI
import UsageCore

/// Mac `PopoverHeader` status line: dot plus "All accounts updated 14:20" / attention count / "Offline".
struct HomeHeader: View {
    var state: AppState
    var calendar: Calendar = .current

    @Environment(\.colorScheme) private var scheme

    static func attentionCount(_ state: AppState) -> Int {
        state.accounts.filter {
            let s = state.statuses[$0] ?? .noData
            return !(s == .fresh || s == .noData)
        }.count
    }

    static func statusLine(_ state: AppState, calendar: Calendar) -> String {
        if state.isOffline { return "Offline" }
        let n = attentionCount(state)
        if n > 0 { return n == 1 ? "1 account needs attention" : "\(n) accounts need attention" }
        guard let at = state.accounts.compactMap({ state.snapshots[$0]?.fetchedAt }).max() else { return "No data yet" }
        let c = calendar.dateComponents([.hour, .minute], from: at)
        return "All accounts updated " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(Self.statusLine(state, calendar: calendar))
        }
        .font(.subheadline)
        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.88) : Color.primary.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        if state.isOffline { return .secondary }
        if Self.attentionCount(state) > 0 {
            return scheme == .dark ? Color(red: 1.0, green: 0.82, blue: 0.45) : GlassStyle.warning
        }
        return scheme == .dark ? Color(red: 0.59, green: 0.93, blue: 0.59) : .green
    }
}
