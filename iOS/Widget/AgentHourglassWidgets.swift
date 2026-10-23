import SwiftUI
import WidgetKit

/// Widget extension entry point. Widgets are added by later P5 tasks.
@main
struct AgentHourglassWidgets: WidgetBundle {
    var body: some Widget {
        EmptyWidget()
        SmallUsageWidget()
        CircularUsageWidget()
        RectangularUsageWidget()
        InlineUsageWidget()
    }
}

/// Placeholder so the bundle body is non-empty until real widgets land.
struct EmptyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentHourglassEmpty", provider: EmptyProvider()) { _ in
            Text("Agent Hourglass").containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([])
    }
}

struct EmptyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry { let date: Date }
