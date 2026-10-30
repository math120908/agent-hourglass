import SwiftUI
import UsageCore

/// Icon-only link to the provider's usage page, next to an account card's title. Hidden when there is none.
/// The title sits inside the row's expand Button, so the link is not placed there: `UsagePageSlot` holds its
/// place in the label and `usagePageLink` draws the real Button over that spot as the row Button's sibling.
struct UsagePageButton: View {
    let kind: ProviderKind
    var open: (URL) -> Void

    var body: some View {
        if let url = kind.usagePageURL {
            Button { open(url) } label: {
                UsagePageIcon()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(ProviderIcon.label(kind)) usage page")
            .accessibilityLabel("Open \(ProviderIcon.label(kind)) usage page")
        }
    }
}

private struct UsagePageIcon: View {
    var body: some View {
        Image(systemName: "arrow.up.right.square")
            .font(.system(size: 10.5, weight: .medium))
            .glassTone()
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
    func usagePageLink(kind: ProviderKind, open: @escaping (URL) -> Void) -> some View {
        overlayPreferenceValue(UsagePageSlotKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let r = proxy[anchor]
                    UsagePageButton(kind: kind, open: open)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }
}
