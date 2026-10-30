import SwiftUI
import UsageCore

/// Accounts tab (spec §10.5): drag to reorder, inline rename, sign in again, remove with confirmation.
struct AccountsTab: View {
    @Bindable var model: SettingsModel
    var addClaude: () -> Void
    var addCopilot: () -> Void = {}
    var addCodex: () -> Void = {}
    var addClaudeCode: () -> Void = {}
    @State private var pendingRemoval: AccountEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.entries.isEmpty {
                ContentUnavailableView("No accounts", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Add a Claude account to start tracking usage."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.entries, id: \.id) { e in
                        AccountRow(entry: e, model: model) { pendingRemoval = e }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.55)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let err = model.error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(GlassStyle.warning)
            }
            HStack {
                Text("Drag to reorder. The popover follows this order.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                // One menu instead of a button per provider, so new providers don't widen the bar.
                Menu {
                    Menu {
                        Button("Claude account (sign in)", action: addClaude)
                        Button("Claude Code (local, read-only)", action: addClaudeCode)
                    } label: { Label { Text("Claude") } icon: { ProviderIcon(kind: .claude) } }
                    Button(action: addCopilot) { Label { Text("GitHub Copilot") } icon: { ProviderIcon(kind: .copilot) } }
                    Button(action: addCodex) { Label { Text("Codex") } icon: { ProviderIcon(kind: .codex) } }
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .fixedSize()
            }
        }
        .padding(16)
        // Accounts added from the Add Account sheet land in appState first; refresh the list then.
        .onChange(of: model.appState.accounts) { model.reload() }
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "account")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { e in
            Button("Remove", role: .destructive) { model.remove(e.id) }
            Button("Cancel", role: .cancel) {}
        } message: { e in
            Text(Self.removeMessage(e))
        }
    }

    static func removeMessage(_ e: AccountEntry) -> String {
        if e.id.isClaudeCodeLocal {
            return "This deletes the account's usage history from this Mac. Claude Code's Keychain login is not touched."
        }
        return switch e.kind {
        case .claude:
            "This deletes the account's saved sign-in and its usage history from this Mac. "
                + "Claude has no revoke endpoint, so the token stays valid on Anthropic's side until it expires."
        case .copilot:
            "This deletes the account's usage history from this Mac. gh is not touched: your gh login is left as is."
        case .codex:
            "This deletes the account's usage history from this Mac. ~/.codex and your Codex CLI login are not touched."
        case .grok:
            "This deletes the account's saved sign-in and its usage history from this Mac. ~/.grok and your grok CLI login are not touched."
        }
    }
}

private struct AccountRow: View {
    var entry: AccountEntry
    var model: SettingsModel
    var onRemove: () -> Void
    @State private var name = ""
    @FocusState private var editing: Bool

    var body: some View {
        let status = model.status(entry.id)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary)
            ProviderIcon(kind: entry.kind, size: 14).foregroundStyle(GlassStyle.accent(entry.kind))
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($editing)
                    .onSubmit(commit)
                    .onChange(of: editing) { _, now in if !now { commit() } }
                HStack(spacing: 6) {
                    Text(entry.remoteLogin ?? entry.kind.rawValue.capitalized)
                    Text("|").foregroundStyle(.tertiary)
                    Text(status.settingsLabel)
                        .foregroundStyle(status.needsAttention ? GlassStyle.warning : .secondary)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.busy == entry.id {
                ProgressView().controlSize(.small)
            }
            if entry.id.isClaudeCodeLocal {
                Button("Try again") { model.reauth(entry.id) }
                    .controlSize(.small)
                    .disabled(model.busy != nil)
            } else if entry.kind == .claude {
                Button("Sign in again") { model.reauth(entry.id) }
                    .controlSize(.small)
                    .disabled(model.busy != nil)
            }
            Button("Remove…", action: onRemove)
                .controlSize(.small)
                .disabled(model.busy != nil)
        }
        .padding(.vertical, 4)
        .onAppear { name = entry.displayName }
        .onChange(of: entry.displayName) { _, n in name = n }
    }

    private func commit() {
        guard name != entry.displayName else { return }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = entry.displayName; return }
        model.rename(entry.id, to: name)
    }
}
