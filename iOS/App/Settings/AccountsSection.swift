import SwiftUI
import UsageCore

/// Settings > Accounts: rename, reorder, remove. Errors show as one red line in the section.
struct AccountsSection: View {
    let model: AppModel
    var rowBackground: Color?
    @Binding var pendingRemove: AccountEntry?
    @State private var error: String?

    /// The name to write, or nil when the edit is blank or unchanged (the field reverts).
    static func committedName(_ edited: String, current: String) -> String? {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == current ? nil : trimmed
    }

    var body: some View {
        Section("Accounts") {
            ForEach(model.entries, id: \.id) { entry in
                AccountRow(entry: entry, status: model.appState.statuses[entry.id] ?? .noData, onCommit: { rename(entry, $0) })
                    .swipeActions {
                        Button("Remove", role: .destructive) { pendingRemove = entry }
                    }
                    .listRowBackground(rowBackground)
            }
            .onMove(perform: move)
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote).listRowBackground(rowBackground)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemove?.displayName ?? "")?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { entry in
            Button("Remove", role: .destructive) { remove(entry) }
        }
    }

    private func rename(_ entry: AccountEntry, _ name: String) {
        run { try await model.rename(entry.id, to: name) }
    }

    private func move(_ from: IndexSet, _ to: Int) {
        var ids = model.entries.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        run { try await model.reorder(ids) }
    }

    private func remove(_ entry: AccountEntry) {
        run { try await model.remove(entry.id) }
    }

    private func run(_ op: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await op()
                error = nil
            } catch {
                self.error = "Something went wrong: \(error.localizedDescription)"
            }
        }
    }
}

private struct AccountRow: View {
    let entry: AccountEntry
    let status: AccountStatus
    let onCommit: (String) -> Void
    @State private var name = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(kind: entry.kind, size: 20).foregroundStyle(GlassStyle.accent(entry.kind))
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .font(.body.weight(.medium))
                    .focused($editing)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .onChange(of: editing) { _, now in if !now { commit() } }
                HStack(spacing: 6) {
                    Text(entry.remoteLogin ?? entry.kind.rawValue.capitalized)
                    Text("|").foregroundStyle(.tertiary)
                    Text(status.settingsLabel)
                        .foregroundStyle(status.needsAttention ? GlassStyle.warning : .secondary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .onAppear { name = entry.displayName }
        .onChange(of: entry.displayName) { _, n in name = n }
    }

    private func commit() {
        if let n = AccountsSection.committedName(name, current: entry.displayName) {
            onCommit(n)
        } else {
            name = entry.displayName
        }
    }
}

extension AccountStatus {
    /// Same strings as the Mac Settings Accounts tab.
    var settingsLabel: String {
        switch self {
        case .fresh: "Up to date"
        case .stale: "Stale"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .needsLogin: "Needs sign-in"
        case .ghMissing: "gh not found"
        case .ghLoginRemoved: "Not in gh"
        case .schemaError: "Unexpected response"
        case .noData: "No data yet"
        case .codexNotSignedIn: "Codex not signed in"
        case .claudeCodeNotSignedIn: "Claude Code not signed in"
        case .claudeCodeExpired: "Run `claude` to refresh login"
        case .claudeCodeDenied: "Keychain access denied"
        case .quotaUnavailable: "Quota unavailable"
        }
    }

    var needsAttention: Bool { !(self == .fresh || self == .noData) }
}
