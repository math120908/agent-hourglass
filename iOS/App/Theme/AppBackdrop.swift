import SwiftUI

/// Full-screen backdrop: the Glass gradient, or the plain system background on Instrument.
struct AppBackdrop: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if theme == .glass {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.20, green: 0.22, blue: 0.30), Color(red: 0.29, green: 0.20, blue: 0.27)]
                    : [Color(red: 0.62, green: 0.68, blue: 0.86), Color(red: 0.78, green: 0.62, blue: 0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.systemBackground)
        }
    }
}
