import SwiftUI
import UsageCore

struct PopoverActions {
    var refresh: () -> Void = {}
    var history: () -> Void = {}
    var settings: () -> Void = {}
    var addAccount: () -> Void = {}
    var signIn: (AccountID) -> Void = { _ in }
    /// schemaError recovery: opens About, where "Copy diagnostics" lives.
    var diagnostics: () -> Void = {}
}

struct PopoverHeader: View {
    var content: PopoverContent
    var actions: PopoverActions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Usage").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(content.statusLine)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            iconButton("plus", "Add account", actions.addAccount)
            iconButton("arrow.clockwise", "Refresh all", actions.refresh)
            iconButton("chart.xyaxis.line", "History", actions.history)
            iconButton("gearshape", "Settings", actions.settings)
        }
    }

    @Environment(\.colorScheme) private var scheme

    /// Dark mode lifts both dots to >= 4.5:1 on the popover material (system green measured 3.7, amber 2.8).
    private var dotColor: Color {
        if content.isOffline { return .secondary }
        if content.attentionCount > 0 {
            return scheme == .dark ? Color(red: 1.0, green: 0.82, blue: 0.45) : GlassStyle.warning
        }
        return scheme == .dark ? Color(red: 0.59, green: 0.93, blue: 0.59) : Color.green
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
