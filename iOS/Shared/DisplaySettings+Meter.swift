import Foundation
import UsageCore

extension DisplaySettings {
    /// Maps stored preferences to portable `MeterDisplayOptions`; `.system` hour mode follows the locale.
    func meterOptions(calendar: Calendar = .current, locale: Locale = .current) -> MeterDisplayOptions {
        let use24Hour: Bool
        switch hour24 {
        case .on: use24Hour = true
        case .off: use24Hour = false
        case .system:
            let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
            use24Hour = !format.contains("a")
        }
        return MeterDisplayOptions(
            showRemaining: showRemaining,
            countdown: resetStyle == .countdown,
            use24Hour: use24Hour,
            calendar: calendar,
            locale: locale
        )
    }
}
