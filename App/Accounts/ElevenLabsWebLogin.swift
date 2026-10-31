import AppKit
import UsageCore
import WebKit

/// ElevenLabs sign-in: an in-app web view with a throwaway (non-persistent) data store loads the
/// sign-in page and polls for the Firebase auth user the page stores once signed in. The refresh token
/// read there is exchanged at once for a fresh ID token; nothing from the page is logged or persisted.
@MainActor
final class ElevenLabsWebLogin: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let signInURL = URL(string: "https://elevenlabs.io/app/sign-in")!
    static let notice = "Sign in with email and password. Google, Apple and SSO sign-in aren't supported here; "
        + "set a password at elevenlabs.io first if you use those."

    /// Collects every `firebase:authUser:*` value from localStorage and Firebase's IndexedDB store.
    private static let probeScript = """
    const out = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && k.startsWith('\(ElevenLabsWebSession.storageKeyPrefix)')) out.push(localStorage.getItem(k));
    }
    if (out.length === 0 && window.indexedDB) {
      try {
        const rows = await new Promise((resolve) => {
          const open = indexedDB.open('firebaseLocalStorageDb');
          open.onupgradeneeded = () => { open.transaction.abort(); resolve([]); };
          open.onerror = () => resolve([]);
          open.onsuccess = () => {
            const db = open.result;
            if (!db.objectStoreNames.contains('firebaseLocalStorage')) { db.close(); resolve([]); return; }
            const req = db.transaction('firebaseLocalStorage', 'readonly').objectStore('firebaseLocalStorage').getAll();
            req.onsuccess = () => { db.close(); resolve(req.result || []); };
            req.onerror = () => { db.close(); resolve([]); };
          };
        });
        for (const r of rows) {
          if (r && typeof r.fbase_key === 'string' && r.fbase_key.startsWith('\(ElevenLabsWebSession.storageKeyPrefix)')) out.push(r.value);
        }
      } catch (e) {}
    }
    return JSON.stringify(out);
    """

    private var window: NSWindow?
    private var webView: WKWebView?
    private var timer: Timer?
    private var continuation: CheckedContinuation<ElevenLabsWebSession, any Error>?

    /// Shows the sign-in window and returns the signed-in session; throws `CancellationError` when the
    /// window is closed or the calling task is cancelled.
    func signIn() async throws -> ElevenLabsWebSession {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                open()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func open() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: config)
        web.isInspectable = false
        web.navigationDelegate = self
        // uiDelegate stays nil: popups (Google / Apple / SSO sign-in) are intentionally unsupported.
        // Google refuses embedded web views anyway, and every extra window widens the attack surface.
        let label = NSTextField(wrappingLabelWithString: Self.notice)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, web])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        label.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12).isActive = true
        label.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12).isActive = true
        web.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        web.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        web.setContentHuggingPriority(.defaultLow, for: .vertical)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 770),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "ElevenLabs"
        w.contentView = stack
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        webView = web
        web.load(URLRequest(url: Self.signInURL))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    private func poll() async {
        guard let webView, continuation != nil, ElevenLabsWebSession.isProbeHost(webView.url?.host) else { return }
        let result = try? await webView.callAsyncJavaScript(Self.probeScript, contentWorld: .defaultClient)
        guard let json = result as? String, let session = ElevenLabsWebSession.parse(json) else { return }
        finish(.success(session))
    }

    private func finish(_ result: Result<ElevenLabsWebSession, any Error>) {
        timer?.invalidate()
        timer = nil
        guard let cont = continuation else { return }
        continuation = nil
        let w = window
        window = nil
        w?.delegate = nil
        w?.close()
        let store = webView?.configuration.websiteDataStore
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        store?.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        cont.resume(with: result)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        // targetFrame is nil for a new-window request: treat it as main frame.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        if ElevenLabsWebSession.isAllowedNavigation(url, isMainFrame: isMainFrame) {
            return decisionHandler(.allow)
        }
        if isMainFrame, navigationAction.navigationType == .linkActivated,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        window?.title = webView.url?.host.map { "ElevenLabs \u{2014} \($0)" } ?? "ElevenLabs"
    }

    func windowWillClose(_ notification: Notification) {
        finish(.failure(CancellationError()))
    }
}
