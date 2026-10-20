import SwiftUI
import UsageCore

/// Measured ideal heights of the popover's parts, reported outside the ScrollView.
struct PopoverHeights: Equatable {
    var content: CGFloat = 0
    var chrome: CGFloat = 0

    /// Viewport for the card list: content height, capped so the popover stays within 600 pt.
    var viewport: CGFloat { CGFloat(PopoverSizing.viewport(content: content, chrome: chrome)) }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct HeightReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var body: some View {
        GeometryReader { Color.clear.preference(key: Key.self, value: $0.size.height) }
    }
}

extension View {
    /// Card list inside the ScrollView: its natural height.
    func measuresContent() -> some View { background(HeightReader<ContentHeightKey>()) }

    /// Header, footer, dividers: everything outside the ScrollView.
    func measuresChrome() -> some View { background(HeightReader<ChromeHeightKey>()) }

    /// Collects content + chrome into `heights`. The ScrollView's frame depends only on these, never on the popover size, so there is no loop.
    func collectsHeights(_ heights: Binding<PopoverHeights>) -> some View {
        onPreferenceChange(ContentHeightKey.self) { h in heights.wrappedValue.content = h }
            .onPreferenceChange(ChromeHeightKey.self) { h in heights.wrappedValue.chrome = h }
    }

}
