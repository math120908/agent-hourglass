import Foundation

/// What the menu bar icon shows. Equal values mean no redraw is needed.
public struct IconState: Equatable, Sendable {
    public enum Level: Equatable, Sendable { case empty, normal, warning, critical, outline }

    public var level: Level
    /// Integer headline percent (0...100), nil when unknown.
    public var percent: Int?
    /// Elapsed window percent for the pace line, nil when unknown.
    public var pace: Int?
    /// Short window caption: "5H" for Claude session, "PR" for Copilot premium.
    public var caption: String
    /// Integer weekly percent (0...100) for the Instrument second bar, nil when unknown.
    public var weekly: Int?

    public init(level: Level, percent: Int?, pace: Int?, caption: String, weekly: Int? = nil) {
        self.level = level
        self.percent = percent
        self.pace = pace
        self.caption = caption
        self.weekly = weekly
    }

    public static let empty = IconState(level: .empty, percent: nil, pace: nil, caption: "")

    public static func make(
        appState snapshots: [AccountID: UsageSnapshot],
        statuses: [AccountID: AccountStatus],
        menuBarAccount: AccountID?,
        order: [AccountID],
        now: Date
    ) -> IconState {
        let candidates = [menuBarAccount].compactMap { $0 } + order
        guard let id = candidates.first(where: { snapshots[$0] != nil || statuses[$0] != nil }) else { return .empty }
        let meter = snapshots[id]?.meters.first { $0.kind == .session5h }
            ?? snapshots[id]?.meters.first { $0.kind == .window }
            ?? snapshots[id]?.meters.first { $0.kind == .copilotPremium && !$0.isUnlimited && ($0.limit ?? 0) > 0 }
        let caption: String
        if meter?.kind == .window, let s = meter?.windowSeconds {
            caption = Meter.windowCaption(seconds: s)
        } else {
            caption = meter?.kind == .copilotPremium || id.kind == .copilot ? "PR" : "5H"
        }
        let percent = meter?.percentUsed.map { Int(min(100, max(0, $0)).rounded()) }
        let pace = meter?.paceFraction(now: now).map { Int(($0 * 100).rounded()) }
        let second = id.kind == .codex ? snapshots[id]?.meters.filter { $0.kind == .window }.dropFirst().first : nil
        let weekly = (second ?? snapshots[id]?.meters.first { $0.kind == .weeklyAll })?.percentUsed
            .map { Int(min(100, max(0, $0)).rounded()) }
        let level: Level
        switch statuses[id] ?? .fresh {
        case .stale, .needsLogin, .codexNotSignedIn: level = .outline
        default:
            guard let percent else { level = .outline; break }
            level = percent >= 90 ? .critical : percent >= 75 ? .warning : .normal
        }
        return IconState(level: level, percent: percent, pace: pace, caption: caption, weekly: weekly)
    }
}
