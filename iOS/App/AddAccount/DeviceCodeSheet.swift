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

    init(model: DeviceCodeFlowModel, provider: ProviderKind, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.provider = provider
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ProviderIcon(kind: provider, size: 20)
                Text(model.title).font(.headline)
            }
            .padding(.top, 24)
            content
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
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
                .buttonStyle(.bordered)
                Button("Open \(prompt.verificationURL.host() ?? "")") { openURL(prompt.verificationURL) }
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting").font(.subheadline).foregroundStyle(.secondary)
            }
        case .expired:
            Text("Code expired").font(.title3)
            Button("Get new code") { copied = false; model.restart() }
                .buttonStyle(.borderedProminent)
        case .success(let id):
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Button("Done") { onDone(id) }
                .buttonStyle(.borderedProminent)
        case .failed(let message):
            Text(message).font(.title3)
            Button("Try again") { copied = false; model.restart() }
                .buttonStyle(.borderedProminent)
        }
    }
}
