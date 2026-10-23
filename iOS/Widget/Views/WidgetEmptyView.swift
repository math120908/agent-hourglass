import SwiftUI

/// Placeholder when no account is chosen or no snapshot exists yet.
struct WidgetEmptyView: View {
    enum Reason: Sendable { case noAccount, noData }

    var family: WidgetFamilyKind
    var style: WidgetRenderStyle
    var reason: Reason = .noAccount

    private var message: String { reason == .noAccount ? "Choose account" : "No data yet" }

    var body: some View {
        switch family {
        case .inline:
            Text(message)
        case .circular:
            Image(systemName: reason == .noAccount ? "person.crop.circle.badge.questionmark" : "hourglass")
                .font(.title3)
                .accessibilityLabel(message)
        case .small, .rectangular:
            VStack(spacing: 4) {
                Image(systemName: "hourglass").font(.title3)
                Text(message).font(.caption.weight(.medium))
            }
            .foregroundStyle(style.text(.secondary))
        }
    }
}
