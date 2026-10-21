import AppKit
import SwiftUI
import UsageCore

/// About tab (spec §10.5).
struct AboutTab: View {
    var model: SettingsModel
    @State private var copied = false

    static let repo = URL(string: "https://github.com/math120908/claude-usage")!

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "dev"
        let commit = info["GitCommit"] as? String ?? "unknown"
        return "\(v) (\(commit))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(GlassStyle.claude)
            Text("Agent Hourglass").font(.system(size: 17, weight: .semibold))
            Text("Version \(Self.version)")
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Link("github.com/math120908/claude-usage", destination: Self.repo)
                .font(.system(size: 12))
            Spacer()
            HStack {
                Text("Diagnostics hash account ids and never include tokens or names.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy diagnostics", action: copy)
            }
        }
        .padding(16)
    }

    private func copy() {
        let s = model.appState
        let accounts = s.accounts.map { id in
            Diagnostics.Account(id: id, kind: id.kind ?? .claude, status: s.statuses[id] ?? .noData, snapshot: s.snapshots[id])
        }
        let text = Diagnostics.report(app: Self.version, accounts: accounts, isOffline: s.isOffline,
                                      interval: s.effectiveInterval, now: Date())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}
