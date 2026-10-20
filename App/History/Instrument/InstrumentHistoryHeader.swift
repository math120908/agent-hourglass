import AppKit
import SwiftUI
import UsageCore

/// Instrument History window (mockup B): compact toolbar, big summary numbers, area chart, legend footer.
struct InstrumentHistoryView: View {
    @Bindable var model: HistoryModel
    var hover: Date?

    private var fmt: HistorySummaryFormatting {
        if model.kind == .copilot {
            let pts = model.lines.filter { $0.style == .copilot }.flatMap(\.points)
            return HistorySummaryFormatting(
                peak: pts.compactMap(\.percent).max(),
                windows: model.summary?.windowsOver90 ?? 0,
                weekly: pts.last { $0.percent != nil }?.percent,
                isEmpty: model.isEmpty
            )
        }
        return HistorySummaryFormatting(summary: model.summary, isEmpty: model.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            InstrumentHistoryToolbar(model: model)
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 0) {
                InstrumentHistoryHeader(model: model, fmt: fmt).padding(.bottom, 10)
                ZStack {
                    InstrumentHistoryChart(lines: model.lines, interval: model.interval, kind: model.kind, hidden: model.hiddenModels, hover: hover)
                        .opacity(model.isEmpty ? 0.35 : 1)
                    if model.isEmpty { empty }
                }
                .frame(minHeight: 220)
                footer.padding(.top, 8)
                if let e = model.error { Text(e).font(.system(size: 11)).foregroundStyle(GlassStyle.critical).padding(.top, 6) }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        }
        .frame(minWidth: 700, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No data in selected range").font(.system(size: 13, weight: .medium))
            Text("History is recorded while the app runs.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.kind == .copilot {
                swatch(GlassStyle.copilot, dashed: false, "Premium")
            } else {
                swatch(GlassStyle.claude, dashed: false, "Session")
                swatch(HistoryChart.weekly, dashed: true, "Weekly")
                ForEach(modelNames, id: \.self) { n in
                    let off = model.hiddenModels.contains(n)
                    Button {
                        if off { model.hiddenModels.remove(n) } else { model.hiddenModels.insert(n) }
                    } label: { swatch(HistoryChart.model, dashed: false, n) }
                        .buttonStyle(.plain)
                        .opacity(off ? 0.5 : 1)
                        .help(off ? "Show \(n)" : "Hide \(n)")
                }
            }
            Spacer()
            Text(fmt.windowsHit90).monospacedDigit()
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
}

/// Big summary numbers and the range stepper.
struct InstrumentHistoryHeader: View {
    @Bindable var model: HistoryModel
    var fmt: HistorySummaryFormatting

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            figure(model.kind == .copilot ? "Premium now" : "Weekly now", fmt.weeklyNow, .primary)
            figure(model.kind == .copilot ? "Peak premium" : "Peak session", fmt.peakSession, model.isEmpty ? .primary : GlassStyle.accent(model.kind))
            Spacer()
            HStack(spacing: 8) {
                Text(HistorySummaryFormatting.rangeLabel(model.interval, isNow: !model.canGoNext))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                ControlGroup {
                    Button { model.offset += 1 } label: { Image(systemName: "chevron.left") }
                        .help("Previous range")
                    Button { model.offset -= 1 } label: { Image(systemName: "chevron.right") }
                        .help("Next range")
                        .disabled(!model.canGoNext)
                }
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.bottom, 4)
        }
    }

    private func figure(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold).monospacedDigit()).tracking(-0.5).foregroundStyle(tint)
        }
    }
}

/// Compact toolbar: account picker, short range segments, Export menu.
struct InstrumentHistoryToolbar: View {
    @Bindable var model: HistoryModel

    static func short(_ r: HistoryRange) -> String {
        switch r {
        case .day: "24H"
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Picker("", selection: $model.account) {
                if model.entries.isEmpty { Text("No accounts").tag(AccountID?.none) }
                ForEach(model.entries, id: \.id) { e in Text(e.displayName).tag(AccountID?.some(e.id)) }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize()
            .disabled(model.entries.isEmpty)
            Picker("", selection: $model.range) {
                ForEach(HistoryRange.allCases) { Text(Self.short($0)).tag($0).help($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            Menu("Export") {
                Button("Export as CSV…") { model.export(.csv, allAccounts: NSEvent.modifierFlags.contains(.option)) }
                Button("Export as JSON…") { model.export(.json, allAccounts: NSEvent.modifierFlags.contains(.option)) }
                Divider()
                Text("Hold ⌥ when choosing to export all accounts")
            }
            .menuStyle(.button).controlSize(.small).fixedSize()
            .disabled(model.store == nil || model.entries.isEmpty)
        }
        .padding(.leading, 80)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(.bar)
    }
}
