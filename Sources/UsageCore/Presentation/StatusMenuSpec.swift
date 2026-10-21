import Foundation

/// Right-click menu on the menu bar icon. `nil` marks a separator.
public enum StatusMenuItem: Equatable, Sendable {
    case refresh, history, settings, quit

    public var title: String {
        switch self {
        case .refresh: "Refresh Now"
        case .history: "Open History…"
        case .settings: "Settings…"
        case .quit: "Quit Agent Hourglass"
        }
    }

    public var keyEquivalent: String {
        switch self {
        case .refresh: "r"
        case .history: "h"
        case .settings: ","
        case .quit: "q"
        }
    }

    public static let layout: [StatusMenuItem?] = [.refresh, .history, .settings, nil, .quit]

    /// Right-click, or ctrl-click, opens the menu; plain left-click toggles the popover.
    public static func opensMenu(isRightMouseUp: Bool, controlHeld: Bool) -> Bool {
        isRightMouseUp || controlHeld
    }
}
