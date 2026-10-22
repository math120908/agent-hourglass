import Foundation

public struct MeterRow: Equatable, Sendable {
    public var label: String
    public var percentText: String
    public var resetText: String
    /// Copilot only: "62,500 / 250,000 credits (≈ $625 / $2,500)".
    public var detailText: String?
    public var fraction: Double?
    public var paceTick: Double?
    public var paceText: String?
    public var severity: Meter.Severity
}

public struct SpendRow: Equatable, Sendable {
    public var text: String
    public var fraction: Double?
    public var chip: String?
}

/// Theme-independent presentation of one account card (spec §9, §10.3–10.4).
public struct CardModel: Equatable, Sendable {
    public var headline: MeterRow?
    public var secondary: String?
    public var rows: [MeterRow]
    public var spend: SpendRow?
    public var planTag: String?
    public var statusChip: String?
    public var updatedText: String
    public var isDimmed: Bool

    static let dollarsPerCredit = 0.01

    public static func make(
        snapshot: UsageSnapshot?,
        status: AccountStatus,
        kind: ProviderKind,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        login: String? = nil,
        saveFailed: Bool = false
    ) -> CardModel {
        let ctx = Ctx(now: now, calendar: calendar, locale: locale)
        let meters = (snapshot?.meters ?? []).filter(isVisible)
        let headlineKind: Meter.Kind = kind == .claude ? .session5h : kind == .codex ? .window : .copilotPremium
        return CardModel(
            headline: meters.first { $0.kind == headlineKind }.map { ctx.row($0) },
            secondary: secondary(meters, kind: kind),
            rows: meters.map { ctx.row($0) },
            spend: snapshot?.spend.map(spendRow),
            planTag: Formatting.planTag(snapshot?.plan),
            statusChip: saveFailed ? "Can't save credential" : chip(status, ctx, kind: kind, login: login),
            updatedText: snapshot.map { ctx.updated($0.fetchedAt) } ?? "No data yet",
            isDimmed: !(status == .fresh || status == .noData)
        )
    }

    /// Claude: weekly-all percent. Codex: the second window, captioned from its length.
    static func secondary(_ meters: [Meter], kind: ProviderKind) -> String? {
        if kind == .codex {
            let windows = meters.filter { $0.kind == .window }
            guard windows.count > 1, let s = windows[1].windowSeconds, let p = windows[1].percentUsed else { return nil }
            let cap = s == 604_800 ? "Wk" : Meter.windowCaption(seconds: s)
            return "\(cap) \(Int(p.rounded()))%"
        }
        return meters.first { $0.kind == .weeklyAll }?.percentUsed.map { "Wk \(Int($0.rounded()))%" }
    }

    static func isVisible(_ m: Meter) -> Bool {
        if m.isUnlimited { return false }
        switch m.kind {
        case .copilotChat, .copilotCompletions: return (m.limit ?? 0) > 0
        default: return true
        }
    }

    static func chip(_ status: AccountStatus, _ ctx: Ctx, kind: ProviderKind = .claude, login: String? = nil) -> String? {
        switch status {
        // Offline is one global banner in the header, never a per-card chip (spec §9).
        case .fresh, .noData, .offline: return nil
        case .stale: return "Stale"
        case .rateLimited(let at): return "Rate limited, retry \(Formatting.clock(at, ctx.calendar))"
        case .needsLogin:
            switch kind {
            case .copilot: return "Run `gh auth login`"
            case .codex: return "Run `codex` to sign in"
            case .claude: return "Sign in again"
            }
        case .codexNotSignedIn: return "Run `codex` to sign in"
        case .claudeCodeNotSignedIn: return "Claude Code not signed in"
        case .claudeCodeExpired: return "Run `claude` to refresh login"
        case .claudeCodeDenied: return "Keychain access denied"
        case .ghMissing: return "Install gh (Homebrew)"
        case .ghLoginRemoved: return "Login \(login.map { "`\($0)` " } ?? "")not in gh; run `gh auth login`"
        case .schemaError: return "Response format changed"
        }
    }

    static func spendRow(_ money: Money) -> SpendRow {
        let used = Formatting.minor(money.usedMinor, exponent: money.exponent)
        let text = money.limitMinor.map { "\(used) / \(Formatting.minor($0, exponent: money.exponent)) \(money.currency)" }
            ?? "\(used) \(money.currency)"
        let fraction = money.limitMinor.flatMap { $0 > 0 ? min(1, Double(money.usedMinor) / Double($0)) : nil }
        let chip: String? = money.isEnabled ? nil : "Disabled: " + (money.disabledReason ?? "off").replacingOccurrences(of: "_", with: " ")
        return SpendRow(text: text, fraction: fraction, chip: chip)
    }

    struct Ctx {
        let now: Date, calendar: Calendar, locale: Locale

        func updated(_ at: Date) -> String {
            let age = now.timeIntervalSince(at)
            if age < 60 { return "Updated just now" }
            if age < 3600 { return "Updated \(Int(age / 60)) min ago" }
            return "Updated \(Formatting.clock(at, calendar))"
        }

        func row(_ m: Meter) -> MeterRow {
            let pace = m.kind == .session5h ? nil : m.paceFraction(now: now)
            var row = MeterRow(
                label: m.label,
                percentText: m.percentUsed.map { "\(Int($0.rounded()))%" } ?? "0%",
                resetText: resetText(m),
                detailText: nil,
                fraction: m.percentUsed.map { min(1, max(0, $0 / 100)) },
                paceTick: pace,
                paceText: nil,
                severity: m.displaySeverity(now: now)
            )
            if let p = m.percentUsed, let pace {
                let diff = Int((p - pace * 100).rounded())
                row.paceText = diff == 0 ? "On pace" : diff > 0 ? "\(diff)% ahead of pace" : "\(-diff)% under pace"
            }
            if m.kind == .copilotPremium {
                let limit = m.limit ?? 0
                if limit <= 0 {
                    row.percentText = "Not included"
                    row.fraction = nil
                    row.severity = .normal
                } else {
                    let used = Int((m.used ?? 0).rounded()), total = Int(limit.rounded())
                    row.detailText = "\(Formatting.grouped(used)) / \(Formatting.grouped(total)) credits"
                        + " (≈ $\(dollars(used)) / $\(dollars(total)))"
                }
            }
            return row
        }

        func dollars(_ credits: Int) -> String {
            Formatting.grouped(Int((Double(credits) * CardModel.dollarsPerCredit).rounded()))
        }

        func resetText(_ m: Meter) -> String {
            guard let at = m.resetsAt else { return "Not started" }
            if at <= now { return "Resetting…" }
            switch m.kind {
            case .session5h:
                return "Resets in \(Formatting.span(at.timeIntervalSince(now))) (\(Formatting.clock(at, calendar)))"
            case .weeklyAll, .weeklyModel:
                return "Resets \(Formatting.pattern("EEE", at, calendar, locale)) \(Formatting.clock(at, calendar))"
            case .copilotPremium, .copilotChat, .copilotCompletions:
                return "Resets \(Formatting.pattern("MMM d", at, calendar, locale))"
            case .window:
                let s = m.windowSeconds ?? 0
                if s < 86400 { return "Resets in \(Formatting.span(at.timeIntervalSince(now))) (\(Formatting.clock(at, calendar)))" }
                if s <= 604_800 { return "Resets \(Formatting.pattern("EEE", at, calendar, locale)) \(Formatting.clock(at, calendar))" }
                return "Resets \(Formatting.pattern("MMM d", at, calendar, locale))"
            }
        }
    }
}
