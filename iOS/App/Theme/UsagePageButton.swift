import SwiftUI
import UsageCore

/// Icon-only link to the provider's usage page in the default browser, next to an account card's title.
/// Hidden when there is none. The icon stays small; the hit area is padded out to 44pt.
struct UsagePageButton: View {
    let kind: ProviderKind

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = kind.usagePageURL {
            Button { openURL(url) } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .glassTone()
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle().inset(by: -14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(ProviderIcon.label(kind)) usage page")
        }
    }
}
