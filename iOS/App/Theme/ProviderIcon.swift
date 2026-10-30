import SwiftUI
import UsageCore

/// Provider logo from the asset catalog (Simple Icons, CC0). Template-rendered so callers pick the color.
/// iOS v1 ships Claude and Codex only; any other kind gets a neutral SF Symbol.
struct ProviderIcon: View {
    let kind: ProviderKind
    var size: CGFloat = 12

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel(Self.label(kind))
    }

    private var image: Image {
        if let name = Self.assetName(kind) { Image(name) } else { Image(systemName: "circle.dashed") }
    }

    static func assetName(_ kind: ProviderKind) -> String? {
        switch kind {
        case .claude: "ProviderClaude"
        case .codex: "ProviderCodex"
        case .copilot: nil
        case .google: nil
        case .grok: nil
        }
    }

    static func label(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Unsupported provider"
        case .google: "Google AI"
        case .grok: "Grok"
        }
    }
}
