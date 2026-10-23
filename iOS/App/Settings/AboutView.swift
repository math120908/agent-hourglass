import SwiftUI
import UIKit

/// About screen (spec §10.5), iOS form of the Mac About tab.
struct AboutView: View {
    static let repo = URL(string: "https://github.com/math120908/agent-hourglass")!

    private let diagnostics: () -> String
    @Environment(\.appTheme) private var theme
    @State private var copied: Bool

    init(diagnostics: @escaping () -> String) {
        self.init(diagnostics: diagnostics, copied: false)
    }

    init(diagnostics: @escaping () -> String, copied: Bool) {
        self.diagnostics = diagnostics
        _copied = State(initialValue: copied)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(GlassStyle.claude)
                    Text("Agent Hourglass").font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Version", value: BuildInfo.version).listRowBackground(rowBackground)
                LabeledContent("Build", value: BuildInfo.build).listRowBackground(rowBackground)
                LabeledContent("Commit") {
                    Text(BuildInfo.commit)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .listRowBackground(rowBackground)
            }
            Section {
                Link("github.com/math120908/agent-hourglass", destination: Self.repo)
                    .listRowBackground(rowBackground)
                Button(copied ? "Copied" : "Copy diagnostics", action: copy)
                    .listRowBackground(rowBackground)
            }
        }
        .scrollContentBackground(theme == .instrument ? .hidden : .automatic)
        .background(theme == .instrument ? Self.instrumentBackground : Color.clear)
        .tint(theme == .instrument ? GlassStyle.claude : Color.accentColor)
        .navigationTitle("About")
    }

    private var rowBackground: Color? {
        theme == .instrument ? Self.instrumentRow : nil
    }

    private static let instrumentBackground = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.07, alpha: 1) : UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
    })
    private static let instrumentRow = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
    })

    private func copy() {
        UIPasteboard.general.string = diagnostics()
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
