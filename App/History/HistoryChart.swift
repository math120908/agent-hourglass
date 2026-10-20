import Charts
import SwiftUI
import UsageCore

/// Glass history chart: session step line, dashed weekly, per-model lines, hover rule and tooltip.
struct HistoryChart: View {
    var lines: [ChartLine]
    var interval: DateInterval
    var kind: ProviderKind
    var hidden: Set<String>
    @State var hover: Date?
    @Environment(\.colorScheme) private var scheme

    static let weekly = Color(red: 0.55, green: 0.49, blue: 0.96)
    /// Per-model lines (e.g. Fable): teal, so they never read as the dashed purple weekly line.
    static let model = Color(red: 0.13, green: 0.66, blue: 0.62)

    private var visible: [ChartLine] { lines.filter { !($0.style == .model && hidden.contains($0.name)) } }

    var body: some View {
        Chart {
            ForEach(visible) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, p in
                    if let v = p.percent {
                        LineMark(x: .value("Time", p.t), y: .value("Percent", v), series: .value("Series", line.id))
                            .interpolationMethod(line.style == .session || line.style == .copilot ? .stepEnd : .linear)
                            .foregroundStyle(color(line.style))
                            .lineStyle(stroke(line.style))
                    }
                }
            }
            if let hover {
                RuleMark(x: .value("Hover", hover))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .trailing, alignment: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(at: hover)
                    }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.09))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: interval.duration <= 86_400 ? 5 : 7)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.09))
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(Self.axis(d, day: interval.duration <= 86_400))
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(pt):
                            guard let frame = proxy.plotFrame else { return }
                            let x = pt.x - geo[frame].origin.x
                            hover = proxy.value(atX: x, as: Date.self).map { min(max($0, interval.start), interval.end) }
                        case .ended: hover = nil
                        }
                    }
            }
        }
    }

    static func axis(_ d: Date, day: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = day ? "HH:mm" : "MMM d"
        return f.string(from: d)
    }

    func color(_ s: ChartLine.Style) -> Color {
        switch s {
        case .session: GlassStyle.claude
        case .weekly: Self.weekly
        case .model: Self.model
        case .copilot: GlassStyle.copilot
        }
    }

    func stroke(_ s: ChartLine.Style) -> StrokeStyle {
        switch s {
        case .session, .copilot: StrokeStyle(lineWidth: 1.8, lineJoin: .round)
        case .weekly: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
        case .model: StrokeStyle(lineWidth: 1.4)
        }
    }

    /// Last known value at or before `t` for each visible meter (step semantics).
    private func value(_ style: ChartLine.Style, name: String? = nil, at t: Date) -> Double? {
        visible.filter { $0.style == style && (name == nil || $0.name == name) }
            .flatMap(\.points).filter { $0.t <= t }.max { $0.t < $1.t }?.percent
    }

    private func tooltip(at t: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(GlassHistoryView.stamp(t))
                .font(.system(size: 10.5, weight: .semibold))
            ForEach(rows(at: t), id: \.0) { name, v, c in
                Text("\(name) \(v.map { "\(Int($0.rounded()))%" } ?? "no data")").font(.system(size: 10.5)).foregroundStyle(c)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    private func rows(at t: Date) -> [(String, Double?, Color)] {
        if kind == .copilot { return [("Premium", value(.copilot, at: t), GlassStyle.copilot)] }
        var out: [(String, Double?, Color)] = [("Session", value(.session, at: t), GlassStyle.claude), ("Weekly", value(.weekly, at: t), Self.weekly)]
        for n in Set(visible.filter { $0.style == .model }.map(\.name)).sorted() {
            out.append((n, value(.model, name: n, at: t), Self.model))
        }
        return out
    }
}
