import SwiftUI
import UsageCore

/// Mockup B: shared header, one hairline-divided account list, "Updated | every N min" footer.
struct InstrumentPopoverBody: View {
    var content: PopoverContent
    @Binding var expanded: Set<AccountID>
    var actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(content: content, actions: actions)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 0) {
                    if content.accounts.isEmpty {
                        Divider()
                        Button("Add a Claude or Copilot account", action: actions.addAccount)
                            .buttonStyle(.link)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    ForEach(content.accounts) { account in
                        Divider()
                        InstrumentAccountRow(
                            account: account,
                            card: account.card(now: content.now, calendar: content.calendar),
                            isExpanded: binding(account.id),
                            onSignIn: { actions.signIn(account.id) },
                            onDiagnostics: actions.diagnostics
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var footer: some View {
        HStack {
            Text(content.lastUpdated.map { "Updated \(content.clock($0)) | every \(intervalMinutes) min" } ?? "Not updated yet")
                .glassTone()
            Spacer()
            Button("History", action: actions.history)
                .buttonStyle(.plain)
                .glassTone()
        }
        .font(.system(size: 11).monospacedDigit())
    }

    private var intervalMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsModel.intervalKey)
        return SettingsModel.intervals.contains(stored) ? stored : 1
    }

    private func binding(_ id: AccountID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
                UserDefaults.standard.set(open, forKey: "cardExpanded.\(id.rawValue)")
            }
        )
    }
}
