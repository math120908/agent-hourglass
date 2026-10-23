import SwiftUI
import UIKit
import UsageCore

struct DeviceCodeSheet: View {
    let model: DeviceCodeFlowModel
    let provider: ProviderKind
    let onDone: (AccountID) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 20

    private var glassDark: Bool { theme == .glass && scheme == .dark }

    init(model: DeviceCodeFlowModel, provider: ProviderKind, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.provider = provider
        self.onDone = onDone
    }

    var body: some View {
        // Same family as the Claude sheet: header, then one card on the shared backdrop.
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ProviderIcon(kind: provider, size: markSize)
                Text(model.title).font(.headline)
            }
            .padding(.top, 24)
            VStack(spacing: 24) { content }
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .sheetCard()
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background { AppBackdrop().ignoresSafeArea() }
        .tint(GlassStyle.accent(provider))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.tint(SheetTone.accentText(provider, scheme))
            }
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .starting:
            ProgressView()
        case .waiting(let prompt):
            Text(prompt.userCode)
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = prompt.userCode
                    copied = true
                }
                .quietBordered(provider, scheme: scheme, glass: theme == .glass)
                Button("Open \(prompt.verificationURL.host() ?? "")") { openURL(prompt.verificationURL) }
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                ProgressView().tint(glassDark ? .white : nil)
                Text("Waiting").font(.subheadline).foregroundStyle(SheetTone.secondary(scheme, glass: theme == .glass))
            }
        case .expired:
            Text("Code expired").font(.title3)
            Button("Get new code") { copied = false; model.restart() }
                .buttonStyle(.borderedProminent)
        case .success(let id):
            SheetStatus(text: "Added", systemImage: "checkmark.circle.fill", tint: SheetTone.success(scheme), font: .title3)
            Button("Done") { onDone(id) }
                .buttonStyle(.borderedProminent)
        case .failed(let message):
            Text(message).font(.title3)
            Button("Try again") { copied = false; model.restart() }
                .buttonStyle(.borderedProminent)
        }
    }
}
