import AppKit
import UsageCore

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
