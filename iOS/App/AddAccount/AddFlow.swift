import SwiftUI
import UsageCore

enum AddFlow: Identifiable, Equatable {
    case claude(loginHint: String?)
    case codex
    case google

    var id: String {
        switch self {
        case .claude(let hint): "claude:\(hint ?? "")"
        case .codex: "codex"
        case .google: "google"
        }
    }

    var kind: ProviderKind {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .google: .google
        }
    }

    /// Google is offered only in a dev build that carries the client secret (SPIKE).
    static func signIn(for entry: AccountEntry, googleConfigured: Bool = BundleGoogleOAuthClient.isConfigured()) -> AddFlow? {
        switch entry.kind {
        case .claude: .claude(loginHint: entry.remoteLogin)
        case .codex: .codex
        case .copilot: nil
        case .google: googleConfigured ? .google : nil
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
            case .google: GoogleFlowView(model: GoogleSignInModel(app: app), onDone: onDone)
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

/// Dismissal ends the sign-in: `GoogleSignInView` cancels the model, which frees the loopback port.
private struct GoogleFlowView: View {
    @State var model: GoogleSignInModel
    let onDone: (AccountID) -> Void

    var body: some View {
        NavigationStack {
            GoogleSignInView(model: model, onDone: onDone)
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
