import Observation
import SwiftUI
import UsageCore
import UsageHistory

/// Settings > History state. Retention feeds `UsageEngine.rawDays` through UserDefaults.
@MainActor @Observable
final class HistorySettings {
    static let shared = HistorySettings()
    static let retentionChoices = [30, 90]

    @ObservationIgnored var store: HistoryStore?
    var rawDays: Int {
        didSet { UserDefaults.standard.set(rawDays, forKey: UsageEngine.rawDaysKey) }
    }
    var sizeBytes: Int64?
    var error: String?
    /// Called after a delete so open views reload.
    @ObservationIgnored var onDelete: () -> Void = {}
    /// Opens the Usage History window; wired by StatusItemController.
    @ObservationIgnored var openHistory: (() -> Void)?

    init(store: HistoryStore? = nil) {
        self.store = store
        rawDays = UsageEngine.rawDays
    }

    func refreshSize() { sizeBytes = store?.fileSizeBytes() }

    func deleteAll() {
        guard let store else { return }
        Task {
            do {
                try await store.deleteAll()
                error = nil
            } catch {
                self.error = "Delete failed: \(error.localizedDescription)"
            }
            refreshSize()
            onDelete()
        }
    }
}

/// History tab (spec §10.5): raw retention, database size, delete all.
struct HistoryTab: View {
    @Bindable var settings: HistorySettings
    @State private var confirming = false

    var body: some View {
        Form {
            if let open = settings.openHistory {
                Section {
                    Button {
                        open()
                    } label: {
                        Label("Open Usage History", systemImage: "chart.xyaxis.line")
                    }
                    .buttonStyle(.link)
                }
            }
            Section {
                Picker("Keep detailed samples for", selection: $settings.rawDays) {
                    ForEach(HistorySettings.retentionChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
                Text("Older samples are kept as hourly summaries for two years.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Database size") {
                    Text(settings.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable")
                        .monospacedDigit()
                }
                HStack {
                    Spacer()
                    Button("Delete all history…", role: .destructive) { confirming = true }
                        .disabled(settings.store == nil)
                }
                if let e = settings.error {
                    Text(e).font(.system(size: 11)).foregroundStyle(GlassStyle.critical)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { settings.refreshSize() }
        .confirmationDialog("Delete all usage history?", isPresented: $confirming) {
            Button("Delete All History", role: .destructive) { settings.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recorded sample for every account is removed. Accounts and sign-ins are kept. This can't be undone.")
        }
    }
}
