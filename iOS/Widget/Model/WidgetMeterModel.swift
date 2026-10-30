import Foundation
import UsageCore

enum WidgetFamilyKind: Sendable {
    case small, circular, rectangular, inline

    var maxRows: Int {
        switch self {
        case .small: 2
        case .circular, .inline: 1
        case .rectangular: 3
        }
    }
}

struct WidgetMeterRow: Equatable, Sendable {
    var key: MeterKey
    var label: String
    var shortLabel: String
    var percentText: String
    var fraction: Double?
    var paceTick: Double?
    var resetText: String
    var severity: Meter.Severity
    var isDimmed: Bool
}

/// Chooses and maps meters for one widget entry. All text comes from `MeterDisplay`.
enum WidgetMeterModel {
    static func visibleMeters(_ s: UsageSnapshot) -> [Meter] { MeterDisplay.visibleMeters(s) }

    /// Configured order, missing keys skipped; empty falls back to the family defaults; truncated to `maxRows`.
    static func resolveMeters(_ keys: [MeterKey], in s: UsageSnapshot, family: WidgetFamilyKind) -> [Meter] {
        let visible = visibleMeters(s)
        func pick(_ ks: [MeterKey]) -> [Meter] { ks.compactMap { k in visible.first(where: k.matches) } }
        var result = pick(keys)
        if result.isEmpty, let kind = s.accountID.kind {
            result = pick(defaultKeys(for: kind, family: family, snapshot: s))
        }
        return Array(result.prefix(family.maxRows))
    }

    static func defaultKeys(for kind: ProviderKind, family: WidgetFamilyKind) -> [MeterKey] {
        let raw: [String]
        switch kind {
        case .claude: raw = ["session5h", "weeklyAll"]
        case .codex: raw = ["window:18000", "window:604800"]
        case .copilot: raw = ["copilotPremium"]
        case .google: raw = ["window:18000:gemini", "window:604800:gemini"]
        case .grok: raw = ["window:604800"]
        }
        return Array(raw.compactMap(MeterKey.init(rawValue:)).prefix(family.maxRows))
    }

    /// Claude rectangular default adds the first weeklyModel present in the snapshot.
    static func defaultKeys(for kind: ProviderKind, family: WidgetFamilyKind, snapshot: UsageSnapshot?) -> [MeterKey] {
        var keys = defaultKeys(for: kind, family: family)
        if kind == .claude, family == .rectangular,
           let model = snapshot.flatMap({ visibleMeters($0).first { $0.kind == .weeklyModel } }) {
            keys.append(MeterKey(model))
        }
        return Array(keys.prefix(family.maxRows))
    }

    static func row(_ m: Meter, at date: Date, settings: DisplaySettings, calendar: Calendar, locale: Locale) -> WidgetMeterRow {
        let d = MeterDisplay.make(m, now: date, options: settings.meterOptions(calendar: calendar, locale: locale))
        return WidgetMeterRow(
            key: MeterKey(m),
            label: d.label,
            shortLabel: shortLabel(m),
            percentText: d.percentText,
            fraction: d.fraction,
            paceTick: d.paceTick,
            resetText: d.resetShort ?? d.resetText,
            severity: d.severity,
            isDimmed: m.resetsAt.map { $0 <= date } ?? false
        )
    }

    static func shortLabel(_ m: Meter) -> String {
        switch m.kind {
        case .session5h: "5H"
        case .weeklyAll: "WK"
        case .weeklyModel: String("\(m.label) WK".prefix(6))
        case .window: Meter.windowCaption(seconds: m.windowSeconds ?? 0)
        case .copilotPremium: "PREM"
        case .copilotChat: "CHAT"
        case .copilotCompletions: "COMP"
        }
    }
}
