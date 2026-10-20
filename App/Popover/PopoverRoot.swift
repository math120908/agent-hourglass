import SwiftUI
import UsageCore

/// Switches on the theme. Content comes from a closure so the live app and fixtures share one path.
struct PopoverRoot: View {
    var theme: Theme
    var content: () -> PopoverContent
    var actions = PopoverActions()
    @State private var expanded: Set<AccountID>

    init(
        theme: Theme,
        initiallyExpanded: Set<AccountID> = [],
        actions: PopoverActions = PopoverActions(),
        content: @escaping () -> PopoverContent
    ) {
        self.theme = theme
        self.content = content
        self.actions = actions
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            switch theme {
            case .glass: GlassPopoverBody(content: content(), expanded: $expanded, actions: actions)
            case .instrument: InstrumentPopoverBody(content: content(), expanded: $expanded, actions: actions)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillOpen)) { _ in
            expanded = Set(content().accounts.map(\.id))
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugToggleFirstCard)) { _ in
            guard let id = content().accounts.first?.id else { return }
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}
