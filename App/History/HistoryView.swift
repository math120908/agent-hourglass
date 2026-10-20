import SwiftUI
import UsageCore

/// History window root (spec §10.7). Switches on theme.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    var theme: Theme = .glass
    /// Snapshot rendering only: pins the hover rule.
    var hover: Date?

    var body: some View {
        switch theme {
        case .instrument: InstrumentHistoryView(model: model, hover: hover)
        case .glass: GlassHistoryView(model: model, hover: hover)
        }
    }
}

struct GlassHistoryView: View {
    @Bindable var model: HistoryModel
    var hover: Date?

    var body: some View {
        VStack(spacing: 0) {
            HistoryToolbar(model: model)
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 8)
                ZStack {
                    HistoryChart(lines: model.lines, interval: model.interval, kind: model.kind, hidden: model.hiddenModels, hover: hover)
                        .opacity(model.isEmpty ? 0.35 : 1)
                    if model.isEmpty { empty }
                }
                .frame(minHeight: 220)
                legend.padding(.top, 8)
                stats.padding(.top, 14)
                if let e = model.error { Text(e).font(.system(size: 11)).foregroundStyle(GlassStyle.critical).padding(.top, 6) }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        }
        .frame(minWidth: 700, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Usage overview").font(.system(size: 13, weight: .semibold))
                Text("Track your usage over time").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                navButton("chevron.left", "Previous range", enabled: true) { model.offset += 1 }
                Text(rangeLabel).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                navButton("chevron.right", "Next range", enabled: model.canGoNext) { model.offset -= 1 }
            }
        }
    }

    /// "Oct 19, 14:42".
    static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: d)
    }

    private var rangeLabel: String {
        "\(Self.stamp(model.interval.start)) to \(Self.stamp(model.interval.end))"
    }

    private func navButton(_ symbol: String, _ help: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(help)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
            Text("No data in selected range").font(.system(size: 13, weight: .medium))
            Text("History is recorded while the app runs.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if model.kind == .copilot {
                swatch(GlassStyle.copilot, dashed: false, "Premium requests")
            } else {
                swatch(GlassStyle.claude, dashed: false, "Session (5h)")
                swatch(HistoryChart.weekly, dashed: true, "All models, weekly")
                ForEach(modelNames, id: \.self) { n in
                    let off = model.hiddenModels.contains(n)
                    Button {
                        if off { model.hiddenModels.remove(n) } else { model.hiddenModels.insert(n) }
                    } label: { swatch(HistoryChart.model, dashed: false, off ? "\(n) (off)" : n) }
                        .buttonStyle(.plain)
                        .opacity(off ? 0.5 : 1)
                        .help(off ? "Show \(n)" : "Hide \(n)")
                }
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var modelNames: [String] {
        let names = Set(model.lines.filter { $0.style == .model }.map(\.name))
        return names.isEmpty && model.kind == .claude ? ["Fable"].filter { model.hiddenModels.contains($0) } : names.sorted()
    }

    private func swatch(_ c: Color, dashed: Bool, _ label: String) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                .stroke(c, style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
                .frame(width: 14, height: 2)
            Text(label)
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 10) {
            stat(model.kind == .copilot ? "Peak premium" : "Peak session", pct(model.kind == .copilot ? copilotPeak : model.summary?.peakSession))
            stat("Windows at 90% or more", model.isEmpty ? "--" : "\(model.summary?.windowsOver90 ?? 0)")
            stat(model.kind == .copilot ? "Premium at range end" : "Weekly at range end", pct(model.kind == .copilot ? copilotEnd : model.summary?.weeklyAtEnd))
        }
    }

    private var copilotPeak: Double? { model.lines.filter { $0.style == .copilot }.flatMap(\.points).compactMap(\.percent).max() }
    private var copilotEnd: Double? { model.lines.filter { $0.style == .copilot }.flatMap(\.points).last { $0.percent != nil }?.percent }

    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "--" }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
