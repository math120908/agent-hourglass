import AppIntents
import WidgetKit

struct SelectAccountMetersIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account and meters"

    @Parameter(title: "Account")
    var account: AccountEntity?

    @Parameter(title: "Meters", size: [.systemSmall: 2, .accessoryRectangular: 3, .accessoryCircular: 1, .accessoryInline: 1])
    var meters: [MeterEntity]?

    init() {}
}
