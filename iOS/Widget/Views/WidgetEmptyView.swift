import SwiftUI

/// Placeholder when no account is chosen or no snapshot exists yet.
struct WidgetEmptyView: View {
    enum Reason: Sendable { case noAccount, noData }

    var family: WidgetFamilyKind
    var style: WidgetRenderStyle
    var reason: Reason = .noAccount

    private var message: String { WidgetFreshness.emptyMessage(hasAccount: reason == .noData) }

    var body: some View {
        switch family {
        case .inline:
            Text(message)
        case .circular:
            VStack(spacing: 1) {
                Image(systemName: reason == .noAccount ? "person.crop.circle.badge.questionmark" : "hourglass")
                    .font(.system(size: 14))
                Text(message)
                    .font(.system(size: 8, weight: .medium))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
        case .small, .rectangular:
            VStack(spacing: 4) {
                Image(systemName: "hourglass").font(.title3)
                Text(message).font(.caption.weight(.medium))
            }
            .foregroundStyle(style.text(.secondary))
        }
    }
}
