import SwiftUI
import WidgetKit

/// Widget extension entry point. The bundle holds the four usage widgets.
@main
struct AgentHourglassWidgets: WidgetBundle {
    var body: some Widget {
        SmallUsageWidget()
        CircularUsageWidget()
        RectangularUsageWidget()
        InlineUsageWidget()
    }
}
