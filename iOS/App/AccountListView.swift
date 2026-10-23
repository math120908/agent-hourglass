import SwiftUI
import UsageCore

/// Pure list of shell status lines plus a footer proving App Group settings are read.
struct AccountListView: View {
    let lines: [ShellStatusLine]
    var theme: Theme = .default
    var showRemaining = false

    init(lines: [ShellStatusLine], theme: Theme = .default, showRemaining: Bool = false) {
        self.lines = lines
        self.theme = theme
        self.showRemaining = showRemaining
    }

    var body: some View {
        NavigationStack {
            List {
                if lines.isEmpty {
                    Text("No accounts")
                } else {
                    ForEach(lines, id: \.id) { Text($0.text) }
                }
                Section {
                    Text("Theme \(theme.rawValue) | Remaining \(showRemaining ? "on" : "off")")
                }
            }
            .navigationTitle("Agent Hourglass")
        }
    }
}
