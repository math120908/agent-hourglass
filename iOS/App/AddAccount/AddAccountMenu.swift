import SwiftUI
import UsageCore

struct AddAccountMenu: View {
    let app: AppModel
    @Binding var present: AddFlow?

    init(app: AppModel, present: Binding<AddFlow?>) {
        self.app = app
        _present = present
    }

    var body: some View {
        Menu {
            AddAccountItems(present: $present)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add account")
    }
}

struct AddAccountItems: View {
    @Binding var present: AddFlow?
    /// Google only in a dev build that carries the client secret (SPIKE).
    var google = BundleGoogleOAuthClient.isConfigured()

    var body: some View {
        Button { present = .claude(loginHint: nil) } label: { item("Claude", .claude) }
        Button { present = .codex } label: { item("Codex", .codex) }
        if google { Button { present = .google } label: { item("Google AI", .google) } }
        Button { present = .grok } label: { item("Grok", .grok) }
        Button { present = .elevenlabs } label: { item("ElevenLabs", .elevenlabs) }
    }

    private func item(_ title: String, _ kind: ProviderKind) -> some View {
        Label { Text(title) } icon: { ProviderIcon(kind: kind, size: 18).foregroundStyle(GlassStyle.accent(kind)) }
    }
}
