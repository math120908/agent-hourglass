import SwiftUI
import UIKit

/// Fixed backdrops so the PNGs are reproducible.
enum Backdrop {
    case homeLight, homeDark, tinted(Color), clear, lockScreen

    @ViewBuilder var view: some View {
        switch self {
        case .homeLight:
            LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.93, green: 0.82, blue: 0.90)], startPoint: .top, endPoint: .bottom)
        case .homeDark:
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.25), Color(red: 0.22, green: 0.08, blue: 0.20)], startPoint: .top, endPoint: .bottom)
        case .tinted(let c):
            LinearGradient(colors: [c.opacity(0.35), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                .background(Color(white: 0.05))
        case .clear:
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
        case .lockScreen:
            LinearGradient(colors: [Color(red: 0.15, green: 0.20, blue: 0.40), Color(red: 0.05, green: 0.05, blue: 0.12)], startPoint: .top, endPoint: .bottom)
        }
    }
}

enum RenderHarness {
    enum RenderError: Error { case noImage(URL), encode(URL) }
    static let scale: CGFloat = 3

    @MainActor
    static func render(_ view: some View, size: CGSize, backdrop: Backdrop, to url: URL) throws {
        let content = ZStack {
            backdrop.view
            view
        }
        .frame(width: size.width, height: size.height)
        // Explicit locale and calendar so renders ignore the simulator's region and 24-hour settings
        // (a fixed-identifier Locale carries no user overrides such as AppleICUForce24HourTime).
        .environment(\.locale, WidgetFixtures.renderLocale)
        .environment(\.calendar, WidgetFixtures.calendar)
        .environment(\.timeZone, WidgetFixtures.calendar.timeZone)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage else { throw RenderError.noImage(url) }
        guard let data = image.pngData() else { throw RenderError.encode(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Renders only the backdrop, for comparing against a widget render.
    @MainActor
    static func backdropImage(_ backdrop: Backdrop, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: backdrop.view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }
}
