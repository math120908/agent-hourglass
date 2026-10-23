import SwiftUI
import UIKit

/// About screen (spec §10.5), iOS form of the Mac About tab.
struct AboutView: View {
    static let repo = URL(string: "https://github.com/math120908/agent-hourglass")!

    private let diagnostics: () -> String
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
                LabeledContent("Version", value: BuildInfo.version)
                LabeledContent("Build", value: BuildInfo.build)
                LabeledContent("Commit") {
                    Text(BuildInfo.commit)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                Link("github.com/math120908/agent-hourglass", destination: Self.repo)
                Button(copied ? "Copied" : "Copy diagnostics", action: copy)
            }
        }
        .navigationTitle("About")
    }

    private func copy() {
        UIPasteboard.general.string = diagnostics()
        copied = true
    }
}
