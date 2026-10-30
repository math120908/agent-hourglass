import SwiftUI
import UsageCore

struct GlassPopoverBody: View {
    var content: PopoverContent
    @Binding var expanded: Set<AccountID>
    var actions: PopoverActions
    @State private var heights = PopoverHeights()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(content: content, actions: actions)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 9)
                .measuresChrome()
            ScrollView {
                VStack(spacing: 7) {
                    if content.accounts.isEmpty {
                        Button("Add a Claude, Copilot or Codex account", action: actions.addAccount)
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
                            onOpenUsagePage: actions.openURL,
                            onDiagnostics: actions.diagnostics,
                            now: content.now,
                            calendar: content.calendar
                        )
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 2)
                .measuresContent()
            }
            .frame(height: heights.viewport)
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 0) {
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .measuresChrome()
        }
        .frame(width: 340)
        .collectsHeights($heights)
        .onChange(of: heights, initial: true) { _, h in
            if h.content > 0 { actions.resize(h.chrome + h.viewport) }
        }
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
            }
        )
    }
}
