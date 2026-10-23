import AuthenticationServices
import SwiftUI
import UIKit
import UsageCore

struct ClaudePasteView: View {
    let model: ClaudeSignInModel
    let onDone: (AccountID) -> Void

    @State private var text: String
    @State private var browser = PasteBrowser()

    init(model: ClaudeSignInModel, onDone: @escaping (AccountID) -> Void) {
        self.init(model: model, text: "", onDone: onDone)
    }

    /// Snapshot hook: prefilled field.
    init(model: ClaudeSignInModel, text: String, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.onDone = onDone
        _text = State(initialValue: text)
    }

    private var parsable: Bool { ClaudeManualCallback.parse(pasted: text) != nil }

    var body: some View {
        Form {
            Section {
                Button("Open sign-in page") { browser.open(model.authorizeURL) }
                    .disabled(model.state != .browsing)
            }
            Section {
                HStack {
                    TextField("code#state", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    PasteButton(payloadType: String.self) { items in
                        if let first = items.first { text = first }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
            Section { status }
        }
        .tint(GlassStyle.claude)
        .navigationTitle("Paste code")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .browsing:
            Button("Continue") { Task { await model.receivePasted(text) } }
                .disabled(!parsable)
        case .exchanging:
            ProgressView()
        case .success(let id):
            Button("Done") { onDone(id) }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
            Button("Try again") {
                text = ""
                model.restart()
            }
        }
    }
}

/// Holds the ASWebAuthenticationSession for the paste flow. The callback is never reached;
/// the user copies the code and closes the sheet.
@MainActor final class PasteBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(_ url: URL) {
        session?.cancel()
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "agenthourglass") { [weak self] _, _ in
            self?.session = nil
        }
        s.prefersEphemeralWebBrowserSession = true
        s.presentationContextProvider = self
        session = s
        s.start()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
