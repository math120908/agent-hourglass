import SwiftUI
import UsageCore

/// Icon-only link to the provider's usage page, next to an account card's title. Hidden when there is none.
struct UsagePageButton: View {
    let kind: ProviderKind
    var open: (URL) -> Void

    var body: some View {
        if let url = kind.usagePageURL {
            Button { open(url) } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10.5, weight: .medium))
                    .glassTone()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(ProviderIcon.label(kind)) usage page")
            .accessibilityLabel("Open \(ProviderIcon.label(kind)) usage page")
        }
    }
}
