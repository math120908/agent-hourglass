import SwiftUI
import UsageCore

/// Icon-only link to the provider's usage page in the default browser, next to an account card's title.
/// Hidden when there is none. The title sits inside the row's tap target, so the link is not placed there:
/// `UsagePageSlot` holds its place in the row and `usagePageLink` draws the real Button over that spot as a sibling.
struct UsagePageButton: View {
    let kind: ProviderKind

    /// The icon stays small; the hit area grows 44pt wide toward the empty space trailing the title and up to
    /// the row's top edge, never over the name/plan chip or the subtitle below.
    static let hitPadding = EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 28)

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = kind.usagePageURL {
            Button { openURL(url) } label: {
                UsagePageIcon()
                    .padding(Self.hitPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(ProviderIcon.label(kind)) usage page")
        }
    }
}

private struct UsagePageIcon: View {
    var body: some View {
        Image(systemName: "arrow.up.right.square")
            .font(.system(size: 11, weight: .medium))
            .glassTone()
            .frame(width: 16, height: 16)
    }
}

/// Reserves the link's space in the title row and reports where it landed.
struct UsagePageSlot: View {
    let kind: ProviderKind

    var body: some View {
        if kind.usagePageURL != nil {
            UsagePageIcon()
                .hidden()
                .anchorPreference(key: UsagePageSlotKey.self, value: .bounds) { $0 }
        }
    }
}

private struct UsagePageSlotKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

extension View {
    /// Draws the usage link over the `UsagePageSlot` inside this view.
    func usagePageLink(kind: ProviderKind) -> some View {
        overlayPreferenceValue(UsagePageSlotKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let r = proxy[anchor]
                    let pad = UsagePageButton.hitPadding
                    UsagePageButton(kind: kind)
                        .offset(x: r.minX - pad.leading, y: r.minY - pad.top)
                }
            }
        }
    }
}
