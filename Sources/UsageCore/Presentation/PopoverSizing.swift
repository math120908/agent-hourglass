import Foundation

/// Popover height rules (spec: max 600 pt, scroll only past the cap).
public enum PopoverSizing {
    public static let maxHeight: Double = 600

    /// Scroll viewport height: the cards' ideal height, shrunk so header + footer + viewport fit the cap.
    public static func viewport(content: Double, chrome: Double, max: Double = maxHeight) -> Double {
        Swift.max(0, Swift.min(content, max - chrome))
    }

    /// Height applied to `NSPopover.contentSize`.
    public static func popoverHeight(_ ideal: Double, max: Double = maxHeight) -> Double {
        Swift.max(1, Swift.min(ideal.rounded(.up), max))
    }
}
