import SwiftUI
import UsageCore
import WidgetKit

struct ShellProbeEntry: TimelineEntry {
    let date: Date
    let lines: [ShellStatusLine]
    let theme: Theme
}

struct ShellProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShellProbeEntry {
        ShellProbeEntry(date: .now, lines: [], theme: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (ShellProbeEntry) -> Void) {
        completion(ShellProbeEntry(date: .now, lines: [], theme: .default))
    }

    static func timeline() async -> Timeline<ShellProbeEntry> {
        let now = Date.now
        let lines = await ShellStatus.load(UsageEnvironment.live(), now: now)
        ShellStatus.log(lines, process: "widget")
        let entry = ShellProbeEntry(date: now, lines: lines, theme: Theme.current(in: AppGroup.defaults))
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ShellProbeEntry>) -> Void) {
        Task { completion(await Self.timeline()) }
    }
}

struct ShellProbeView: View {
    let entry: ShellProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.lines.isEmpty {
                Text("No accounts").font(.caption)
            } else {
                ForEach(entry.lines.prefix(3), id: \.id) { line in
                    Text("\(line.name) \(Self.age(line.snapshotAge))").font(.caption)
                }
            }
            Text("key \(entry.lines.filter(\.hasCredential).count)").font(.caption)
            Text(entry.theme.rawValue).font(.caption)
        }
    }

    private static func age(_ age: TimeInterval?) -> String {
        guard let age else { return "no snapshot" }
        let s = max(0, Int(age))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

struct ShellProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentHourglassShellProbe", provider: ShellProbeProvider()) { entry in
            ShellProbeView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Hourglass")
        .supportedFamilies([.systemSmall])
    }
}
