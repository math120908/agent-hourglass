import AppKit

/// Visual theme. Glass is the default; Instrument is mockup B.
public enum Theme: String, CaseIterable, Codable, Sendable {
    case glass
    case instrument

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
    case .instrument: InstrumentIconRenderer()
    }
}
