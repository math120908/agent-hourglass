import SwiftUI
import UsageCore

/// General tab (spec §10.5). Theme picker is added in P7; launch at login lands in P6.
struct GeneralTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $model.intervalMinutes) {
                    ForEach(SettingsModel.intervals, id: \.self) { m in
                        Text(m == 1 ? "1 minute" : "\(m) minutes").tag(m)
                    }
                }
                Text("Applies while the popover is open. In the background, accounts refresh every 5 minutes.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                Picker("Menu bar shows", selection: menuBarBinding) {
                    if model.entries.isEmpty { Text("No accounts").tag(AccountID?.none) }
                    ForEach(model.entries, id: \.id) { e in
                        Text(e.displayName).tag(AccountID?.some(e.id))
                    }
                }
                .disabled(model.entries.isEmpty)
            }
            Section {
                Toggle("Launch at login", isOn: .constant(false))
                    .disabled(true)
                Text("Coming in a later update.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var menuBarBinding: Binding<AccountID?> {
        Binding(get: { model.menuBarAccount }, set: { if let id = $0 { model.chooseMenuBar(id) } })
    }
}
