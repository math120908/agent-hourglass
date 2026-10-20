import AppKit

/// Visual theme. v1 ships Glass only; Instrument arrives in P7 as a new case.
public enum Theme: String, CaseIterable, Codable, Sendable {
    case glass

    public static let `default`: Theme = .glass

    /// Unknown or missing stored values fall back to the default.
    public init(storedValue: String?) {
        self = storedValue.flatMap(Theme.init(rawValue:)) ?? .default
    }
}

public protocol MenuBarIconRendering {
    func image(for state: IconState) -> NSImage
}

/// The single place that maps a theme to its menu bar icon renderer.
public func iconRenderer(for theme: Theme) -> MenuBarIconRendering {
    switch theme {
    case .glass: GlassIconRenderer()
    }
}
