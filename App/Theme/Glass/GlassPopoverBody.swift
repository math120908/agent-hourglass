import SwiftUI
import UsageCore

struct GlassPopoverBody: View {
    var content: PopoverContent
    @Binding var expanded: Set<AccountID>
    var actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(content: content, actions: actions)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 9)
            ScrollView {
                VStack(spacing: 7) {
                    if content.accounts.isEmpty {
                        Button("Add a Claude or Copilot account", action: actions.addAccount)
                            .buttonStyle(.link)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    ForEach(content.accounts) { account in
                        GlassAccountCard(
                            account: account,
                            card: account.card(now: content.now, calendar: content.calendar),
                            isExpanded: binding(account.id),
                            onSignIn: { actions.signIn(account.id) },
                            onDiagnostics: actions.diagnostics
                        )
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var footer: some View {
        HStack {
            Text(content.lastUpdated.map { "Updated \(content.clock($0))" } ?? "Not updated yet")
            Spacer()
            Button("Open history", action: actions.history).buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
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
