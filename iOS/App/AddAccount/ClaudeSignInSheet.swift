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
            web
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if model.state == .exchanging {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            ProgressView()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
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
