import SwiftUI
import UsageCore

extension EnvironmentValues {
    @Entry var appTheme: Theme = .glass
    @Entry var displaySettings: DisplaySettings = .default
}

extension View {
    /// App-wide theme: environment value plus the Instrument accent tint. Apply once at the root.
    func appTheme(_ theme: Theme) -> some View {
        environment(\.appTheme, theme)
            .tint(theme == .instrument ? GlassStyle.claude : Color.accentColor)
    }
}
