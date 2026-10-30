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
        case .grok: nil
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
        .tint(GlassStyle.fill(flow.kind))
    }
}

private struct ClaudeFlowView: View {
    @State var model: ClaudeSignInModel
    let onDone: (AccountID) -> Void

    var body: some View {
        NavigationStack {
            ClaudeSignInView(model: model, onDone: onDone)
        }
    }
}

private struct CodexFlowView: View {
    @State var model: DeviceCodeFlowModel
    let onDone: (AccountID) -> Void

    var body: some View {
        NavigationStack {
            DeviceCodeSheet(model: model, onDone: onDone)
        }
        .task { model.begin() }
    }
}
