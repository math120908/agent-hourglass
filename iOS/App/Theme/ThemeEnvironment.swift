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

/// Extra content appended to an account card (the app injects the Codex reset radar; the widget
/// leaves it nil). Lives here so `App/Theme` stays extension-safe.
struct CardAccessory {
    let make: @MainActor (_ kind: ProviderKind, _ now: Date, _ calendar: Calendar, _ horizontalPadding: CGFloat) -> AnyView
}

extension EnvironmentValues {
    @Entry var cardAccessory: CardAccessory?
}

/// Renders the injected `cardAccessory`, if any.
struct CardAccessorySlot: View {
    var kind: ProviderKind
    var now: Date
    var calendar: Calendar
    var horizontalPadding: CGFloat
    @Environment(\.cardAccessory) private var accessory

    var body: some View {
        if let accessory { accessory.make(kind, now, calendar, horizontalPadding) }
    }
}
