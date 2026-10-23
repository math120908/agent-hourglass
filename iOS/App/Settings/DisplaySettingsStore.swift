import Foundation
import Observation
import WidgetKit

/// App-side owner of `DisplaySettings`. Every change is saved and the widget timelines reload.
@MainActor @Observable
final class DisplaySettingsStore {
    private let defaults: UserDefaults

    var settings: DisplaySettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = DisplaySettings.load(from: defaults)
    }

    func toggleResetStyle() {
        settings.resetStyle = settings.resetStyle == .clock ? .countdown : .clock
    }
}
