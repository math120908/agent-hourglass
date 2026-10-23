import SwiftUI
import Testing
import UIKit
@testable import AgentHourglass

private final class FrameBox: @unchecked Sendable {
    var frame: CGRect = .zero
}

/// Reports its own frame in the hosting window's coordinates.
private struct FrameProbe: View {
    let box: FrameBox
    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { box.frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in box.frame = f }
        }
    }
}

@MainActor
struct ClaudeSignInSheetLayoutTests {
    /// F3: the web viewport must end above the "Paste code instead" bar, so page-fixed
    /// bottom banners (claude.ai's cookie settings) stay reachable.
    @Test(arguments: [ClaudeSignInModel.State.browsing, .exchanging])
    func testWebViewEndsAboveThePasteBar(_ state: ClaudeSignInModel.State) async throws {
        let webBox = FrameBox()
        let sheet = ClaudeSignInSheet(
            model: ClaudeSignInModel(state: state),
            web: FrameProbe(box: webBox),
            onPasteInstead: {},
            onDone: { _ in }
        )
        let host = UIHostingController(rootView: NavigationStack { sheet })
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()

        let bottom = window.bounds.height - host.view.safeAreaInsets.bottom
        #expect(webBox.frame.height > 0)
        // The bar is a 12pt-padded button (>= 44pt). Anything under 30pt above the safe bottom
        // means the web view runs underneath the bar.
        #expect(webBox.frame.maxY <= bottom - 30, "web maxY \(webBox.frame.maxY), safe bottom \(bottom)")
    }
}
