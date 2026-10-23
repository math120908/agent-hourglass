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

    var body: some View {
        Button { present = .claude(loginHint: nil) } label: { item("Claude", .claude) }
        Button { present = .codex } label: { item("Codex", .codex) }
    }

    private func item(_ title: String, _ kind: ProviderKind) -> some View {
        Label { Text(title) } icon: { ProviderIcon(kind: kind, size: 18).foregroundStyle(GlassStyle.accent(kind)) }
    }
}
