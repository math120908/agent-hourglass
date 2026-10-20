import AppKit
import Observation
import UniformTypeIdentifiers
import UsageCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24 Hours", week = "7 Days", month = "30 Days", quarter = "90 Days"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 90 * 86_400
        }
    }
}

/// One plotted line segment: a meter within one reset window.
struct ChartLine: Identifiable, Equatable {
    enum Style { case session, weekly, model, copilot }
    var id: String
    var name: String
    var style: Style
    var points: [SeriesPoint]
}

@MainActor @Observable
final class HistoryModel {
    var entries: [AccountEntry] = []
    var account: AccountID? { didSet { if oldValue != account { offset = 0; load() } } }
    var range: HistoryRange = .day { didSet { if oldValue != range { offset = 0; load() } } }
    /// Number of whole ranges stepped back from now.
    var offset = 0 { didSet { if oldValue != offset { load() } } }
    var lines: [ChartLine] = []
    var summary: RangeSummary?
    var hiddenModels: Set<String> = []
    var error: String?

    @ObservationIgnored let store: HistoryStore?
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var anchor: Date

    init(store: HistoryStore?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        anchor = now()
    }

    var interval: DateInterval {
        let end = anchor.addingTimeInterval(-Double(offset) * range.seconds)
        return DateInterval(start: end.addingTimeInterval(-range.seconds), end: end)
    }

    var canGoNext: Bool { offset > 0 }
    var isEmpty: Bool { !lines.contains { $0.points.contains { $0.percent != nil } } }
    var kind: ProviderKind { entries.first { $0.id == account }?.kind ?? .claude }

    func show(entries: [AccountEntry]) {
        self.entries = entries
        anchor = now()
        if account == nil || !entries.contains(where: { $0.id == account }) {
            account = entries.first?.id
        } else {
            load()
        }
    }

    func load() {
        guard let store, let account else { lines = []; return }
        let q = HistoryQuery(store: store)
        let iv = interval
        Task {
            do {
                let s = try await q.series(account: account, range: iv)
                let sum = try await q.summary(account: account, range: iv)
                guard account == self.account, iv == self.interval else { return }
                lines = s.map(Self.line)
                summary = sum
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    static func line(_ s: Series) -> ChartLine {
        let style: ChartLine.Style
        var name = s.meter
        switch s.meter {
        case Meter.Kind.session5h.rawValue: style = .session; name = "Session (5h)"
        case Meter.Kind.weeklyAll.rawValue: style = .weekly; name = "All models, weekly"
        case let m where m.hasPrefix(Meter.Kind.weeklyModel.rawValue + ":"):
            style = .model; name = String(m.dropFirst(Meter.Kind.weeklyModel.rawValue.count + 1))
        default: style = .copilot; name = "Premium requests"
        }
        return ChartLine(id: s.id, name: name, style: style, points: s.points)
    }

    // MARK: Export

    func export(_ format: ExportFormat, allAccounts: Bool) {
        guard let store else { return }
        let picked = allAccounts ? entries : entries.filter { $0.id == account }
        guard !picked.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "claude-usage-history.\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iv = interval
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Task {
            do {
                try await Exporter(store: store).export(format: format, accounts: picked, range: iv, to: url, appVersion: version)
            } catch {
                self.error = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
