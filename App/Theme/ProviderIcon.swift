import SwiftUI
import UsageCore

/// Provider logo from the asset catalog (Simple Icons, CC0). Template-rendered so callers pick the color.
struct ProviderIcon: View {
    let kind: ProviderKind
    var size: CGFloat = 12

    var body: some View {
        Self.image(kind)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel(Self.label(kind))
    }

    /// ElevenLabs ships no asset; the `waveform` SF Symbol stands in.
    static func image(_ kind: ProviderKind) -> Image {
        assetName(kind).map { Image($0) } ?? Image(systemName: "waveform")
    }

    static func assetName(_ kind: ProviderKind) -> String? {
        switch kind {
        case .claude: "ProviderClaude"
        case .copilot: "ProviderCopilot"
        case .codex: "ProviderCodex"
        case .google: "ProviderGoogle"
        case .grok: "ProviderGrok"
        case .elevenlabs: nil
        }
    }

    static func label(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .copilot: "GitHub Copilot"
        case .codex: "Codex"
        case .google: "Google AI"
        case .grok: "Grok"
        case .elevenlabs: "ElevenLabs"
        }
    }
}
