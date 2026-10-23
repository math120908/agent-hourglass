import SwiftUI
import UsageCore

struct ClaudeSignInSheet<Web: View>: View {
    let model: ClaudeSignInModel
    let web: Web
    let onPasteInstead: () -> Void
    let onDone: (AccountID) -> Void

    @Environment(\.dismiss) private var dismiss

    init(model: ClaudeSignInModel, web: Web, onPasteInstead: @escaping () -> Void, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.web = web
        self.onPasteInstead = onPasteInstead
        self.onDone = onDone
    }

    var body: some View {
        content
            .tint(GlassStyle.claude)
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .browsing, .exchanging:
            // Stacked, not inset: the web viewport ends at the top of the bar, so page-fixed
            // bottom banners (claude.ai's cookie settings) stay reachable.
            VStack(spacing: 0) {
                web
                    // A new authorize URL gets a fresh web view; a torn-down one is never reused.
                    .id(model.authorizeURL)
                    .overlay {
                        if model.state == .exchanging {
                            ZStack {
                                Rectangle().fill(.ultraThinMaterial)
                                ProgressView()
                            }
                        }
                    }
                Button("Paste code instead", action: onPasteInstead)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.bar)
                    .disabled(model.state == .exchanging)
            }
        case .success(let id):
            message {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Button("Done") { onDone(id) }.buttonStyle(.borderedProminent)
            }
        case .failed(let text):
            message {
                Text(text).font(.title3).multilineTextAlignment(.center)
                Button("Try again") { model.restart() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func message<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 24) { c() }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
