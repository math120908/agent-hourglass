import Charts
import SwiftUI
import UsageCore

/// Instrument history chart: area-filled session steps, dashed weekly, model lines, hover rule.
struct InstrumentHistoryChart: View {
    var lines: [ChartLine]
    var interval: DateInterval
    var kind: ProviderKind
    var hidden: Set<String>
    @State var hover: Date?

    private var visible: [ChartLine] { lines.filter { !($0.style == .model && hidden.contains($0.name)) } }
    private var day: Bool { interval.duration <= 86_400 }

    var body: some View {
        Chart {
            ForEach(visible) { line in
                let filled = line.style == .session || line.style == .copilot
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, p in
                    if let v = p.percent {
                        if filled {
                            AreaMark(x: .value("Time", p.t), y: .value("Percent", v), series: .value("Series", line.id))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(color(line.style).opacity(0.14))
                        }
                        LineMark(x: .value("Time", p.t), y: .value("Percent", v), series: .value("Series", line.id))
                            .interpolationMethod(filled ? .stepEnd : .linear)
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
            AxisMarks(values: .automatic(desiredCount: day ? 5 : 7)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.primary.opacity(0.14))
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(HistoryChart.axis(d, day: day)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
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
                            hover = proxy.value(atX: pt.x - geo[frame].origin.x, as: Date.self)
                                .map { min(max($0, interval.start), interval.end) }
                        case .ended: hover = nil
                        }
                    }
            }
        }
    }

    func color(_ s: ChartLine.Style) -> Color {
        switch s {
        case .session: GlassStyle.claude
        case .weekly: HistoryChart.weekly
        case .model: HistoryChart.model
        case .copilot: GlassStyle.copilot
        }
    }

    private func stroke(_ s: ChartLine.Style) -> StrokeStyle {
        switch s {
        case .session, .copilot: StrokeStyle(lineWidth: 1.8, lineJoin: .round)
        case .weekly: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
        case .model: StrokeStyle(lineWidth: 1.4)
        }
    }

    private func value(_ style: ChartLine.Style, name: String? = nil, at t: Date) -> Double? {
        visible.filter { $0.style == style && (name == nil || $0.name == name) }
            .flatMap(\.points).filter { $0.t <= t }.max { $0.t < $1.t }?.percent
    }

    private func tooltip(at t: Date) -> some View {
        var rows: [(String, Double?, Color)] = kind == .copilot
            ? [("Premium", value(.copilot, at: t), GlassStyle.copilot)]
            : [("Session", value(.session, at: t), GlassStyle.claude), ("Weekly", value(.weekly, at: t), HistoryChart.weekly)]
        if kind == .claude {
            for n in Set(visible.filter { $0.style == .model }.map(\.name)).sorted() {
                rows.append((n, value(.model, name: n, at: t), HistoryChart.model))
            }
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(GlassHistoryView.stamp(t)).font(.system(size: 10.5, weight: .semibold))
            ForEach(rows, id: \.0) { name, v, c in
                Text("\(name) \(v.map { "\(Int($0.rounded()))%" } ?? "no data")").font(.system(size: 10.5)).foregroundStyle(c)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }
}
