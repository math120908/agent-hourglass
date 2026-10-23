import SwiftUI
import WidgetKit

struct ShellProbeEntry: TimelineEntry {
    let date: Date
}

struct ShellProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShellProbeEntry { ShellProbeEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ShellProbeEntry) -> Void) {
        completion(ShellProbeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShellProbeEntry>) -> Void) {
        completion(Timeline(entries: [ShellProbeEntry(date: .now)], policy: .never))
    }
}

struct ShellProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentHourglassShellProbe", provider: ShellProbeProvider()) { _ in
            Text("–")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

@main
struct AgentHourglassWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShellProbeWidget()
    }
}
