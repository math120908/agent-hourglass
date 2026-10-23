import SwiftUI
import UsageCore

enum AddFlow: Identifiable, Equatable {
    case claude(loginHint: String?)
    case codex

    var id: String {
        switch self {
        case .claude(let hint): "claude:\(hint ?? "")"
        case .codex: "codex"
        }
    }

    var kind: ProviderKind {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }

    static func signIn(for entry: AccountEntry) -> AddFlow? {
        switch entry.kind {
        case .claude: .claude(loginHint: entry.remoteLogin)
        case .codex: .codex
        case .copilot: nil
        }
    }
}

/// Sheet content for one add flow. Dismissal tears down the flow's work.
struct AddFlowSheet: View {
    let flow: AddFlow
    let app: AppModel
    let onDone: (AccountID) -> Void

    var body: some View {
        Group {
            switch flow {
            case .claude(let hint): ClaudeFlowView(model: ClaudeSignInModel(app: app, loginHint: hint), onDone: onDone)
            case .codex: CodexFlowView(model: CodexAddFlow.model(app: app), onDone: onDone)
            }
        }
        .tint(GlassStyle.accent(flow.kind))
    }
}

private struct ClaudeFlowView: View {
    @State var model: ClaudeSignInModel
    let onDone: (AccountID) -> Void
    @State private var path: [Int] = []
    @State private var exchange: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $path) {
            ClaudeSignInSheet(
                model: model,
                web: ClaudeWebView(url: model.authorizeURL) { code, state in
                    exchange = Task { await model.receive(code: code, state: state) }
                },
                onPasteInstead: { path = [0] },
                onDone: onDone,
            )
            .navigationDestination(for: Int.self) { _ in ClaudePasteView(model: model, onDone: onDone) }
        }
        .onDisappear { exchange?.cancel() }
    }
}

private struct CodexFlowView: View {
    @State var model: DeviceCodeFlowModel
    let onDone: (AccountID) -> Void

    var body: some View {
        NavigationStack {
            DeviceCodeSheet(model: model, provider: .codex, onDone: onDone)
        }
        .task { model.begin() }
    }
}
