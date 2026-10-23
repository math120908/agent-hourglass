import SwiftUI

/// The Glass card surface: thin material, soft-light lift, 0.5 pt hairline, faint shadow.
struct GlassCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                            .blendMode(.softLight)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 0.5)
    }
}

extension View {
    func glassCardBackground() -> some View { modifier(GlassCardBackground()) }
}
