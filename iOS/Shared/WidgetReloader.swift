import Foundation
import os
import WidgetKit

/// Single entry point for app-side widget timeline reloads.
enum WidgetReloader {
    /// Minimum gap between throttled (foreground-poll) reloads.
    static let minInterval: TimeInterval = 60
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "WidgetReloader")

    static func reloadAll() {
        log.debug("reloadAllTimelines")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True for the first reload, then at most once per `minInterval`.
    static func shouldReload(lastReload: Date?, now: Date) -> Bool {
        guard let lastReload else { return true }
        return now.timeIntervalSince(lastReload) >= minInterval
    }
}
