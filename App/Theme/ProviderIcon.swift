import SwiftUI
import UsageCore

/// Provider logo from the asset catalog (Simple Icons, CC0). Template-rendered so callers pick the color.
struct ProviderIcon: View {
    let kind: ProviderKind
    var size: CGFloat = 12

    var body: some View {
        Image(Self.assetName(kind))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel(Self.label(kind))
    }

    static func assetName(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "ProviderClaude"
        case .copilot: "ProviderCopilot"
        case .codex: "ProviderCodex"
        }
    }

    static func label(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .copilot: "GitHub Copilot"
        case .codex: "Codex"
        }
    }
}
