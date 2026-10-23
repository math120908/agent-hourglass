import SwiftUI
import UsageCore

/// Root screen: status header plus one card per account, themed Glass or Instrument.
struct HomeView: View {
    let model: AppModel
    let addMenu: AnyView
    let onSignIn: (AccountEntry) -> Void
    let openSettings: () -> Void

    init(model: AppModel, addMenu: AnyView, onSignIn: @escaping (AccountEntry) -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.addMenu = addMenu
        self.onSignIn = onSignIn
        self.openSettings = openSettings
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HomeContent(
                state: model.appState,
                entries: model.entries,
                settings: model.displayStore.settings,
                now: ctx.date,
                addMenu: addMenu,
                focused: Binding(get: { model.focusedAccount }, set: { model.focusedAccount = $0 }),
                actions: { entry in
                    CardActions(
                        signIn: { onSignIn(entry) },
                        copyDiagnostics: { UIPasteboard.general.string = model.diagnosticsReport() },
                        toggleReset: { model.displayStore.toggleResetStyle() }
                    )
                },
                openSettings: openSettings,
                refresh: { await model.refresh() }
            )
        }
    }
}

/// Model-free body of `HomeView`, so snapshots can drive it from fixtures.
struct HomeContent: View {
    var state: AppState
    var entries: [AccountEntry]
    var settings: DisplaySettings
    var now: Date
    var addMenu: AnyView
    @Binding var focused: AccountID?
    var actions: (AccountEntry) -> CardActions
    var openSettings: () -> Void
    var refresh: () async -> Void
    var calendar: Calendar = .current

    @Environment(\.appTheme) private var theme
    @State private var collapsed: Set<AccountID> = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if entries.isEmpty {
                        ContentUnavailableView {
                            Label("No accounts", systemImage: "person.crop.circle.badge.plus")
                        } actions: {
                            addMenu
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        list
                    }
                }
                .onChange(of: focused, initial: true) { _, id in
                    guard let id else { return }
                    collapsed.remove(id)
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                    focused = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackdrop().ignoresSafeArea() }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
        }
    }

    private var list: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !entries.isEmpty {
                            HomeHeader(state: state, calendar: calendar)
                                .padding(.horizontal, 4)
                            cards
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await refresh() }
    }

    @ViewBuilder private var cards: some View {
        if theme == .glass {
            VStack(spacing: 10) {
                ForEach(entries, id: \.id) { e in
                    GlassAccountCard(
                        entry: e,
                        snapshot: state.snapshots[e.id],
                        status: state.statuses[e.id] ?? .noData,
                        settings: settings,
                        now: now,
                        isExpanded: expanded(e.id),
                        actions: actions(e),
                        calendar: calendar
                    )
                    .id(e.id)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Divider() }
                    InstrumentAccountRow(
                        entry: e,
                        snapshot: state.snapshots[e.id],
                        status: state.statuses[e.id] ?? .noData,
                        settings: settings,
                        now: now,
                        isExpanded: expanded(e.id),
                        actions: actions(e),
                        calendar: calendar
                    )
                    .id(e.id)
                }
            }
        }
    }

    private func expanded(_ id: AccountID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } }
        )
    }
}
