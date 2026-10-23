import SwiftUI
import UsageCore
import WebKit

/// Claude sign-in web view. Ephemeral data store, no script bridge, no injected scripts; every
/// navigation goes through `ClaudeWebAuthPolicy`. The callback is cancelled (never loads), handed to
/// `onCapture` once, and the web view is torn down. Nothing here logs URLs, codes or state.
struct ClaudeWebView: UIViewRepresentable {
    let url: URL
    let onCapture: (String, String) -> Void

    init(url: URL, onCapture: @escaping (String, String) -> Void) {
        self.url = url
        self.onCapture = onCapture
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        context.coordinator.loaded = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onCapture = onCapture
        // A restart yields a new authorize URL: reload it.
        if context.coordinator.loaded != url {
            context.coordinator.loaded = url
            context.coordinator.captured = false
            web.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        teardown(web)
    }

    static func teardown(_ web: WKWebView) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCapture: (String, String) -> Void
        var loaded: URL?
        var captured = false

        init(onCapture: @escaping (String, String) -> Void) { self.onCapture = onCapture }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void,
        ) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            switch ClaudeWebAuthPolicy.decide(url) {
            case .allow:
                decisionHandler(.allow)
            case .block:
                decisionHandler(.cancel)
            case .capture(let code, let state):
                decisionHandler(.cancel)
                guard !captured else { return }
                captured = true
                ClaudeWebView.teardown(webView)
                onCapture(code, state)
            }
        }
    }
}
