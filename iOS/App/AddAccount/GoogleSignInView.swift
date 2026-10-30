import SwiftUI
import UsageCore

/// SPIKE, dev builds only: Google sign-in in one step. The button opens Google in the ephemeral
/// auth sheet; the loopback listener takes the code and the sheet closes itself.
/// Same skeleton as `ClaudeSignInView`: the card carries one line per state.
struct GoogleSignInView: View {
    let model: GoogleSignInModel
    let onDone: (AccountID) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    private var state: GoogleSignInModel.State { model.state }
    private var isGlass: Bool { theme == .glass }

    var body: some View {
        SignInSheetLayout(kind: .google, title: "Add Google AI account", lead: "Sign in with the Google account that has your AI Pro or Ultra plan.") {
            line.padding(14).frame(minHeight: 56)
        } primary: {
            primary
        }
        .onChange(of: state) { _, s in
            if case .success = s { AccessibilityNotification.Announcement("Added").post() }
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var line: some View {
        switch state {
        case .idle:
            Label("Opens accounts.google.com", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(SheetTone.secondary(scheme, glass: isGlass))
                .frame(maxWidth: .infinity)
        case .waiting:
            HStack(spacing: 8) {
                ProgressView().tint(isGlass && scheme == .dark ? .white : nil)
                Text("Waiting for Google").font(.subheadline).foregroundStyle(SheetTone.secondary(scheme, glass: isGlass))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        case .success:
            SheetStatus(text: "Added", systemImage: "checkmark.circle.fill", tint: SheetTone.success(scheme))
        case .failed(let message):
            SheetStatus(
                text: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: SheetTone.criticalGlyph(scheme),
                font: .subheadline,
            )
        }
    }

    @ViewBuilder private var primary: some View {
        switch state {
        case .idle:
            Button(action: model.start) { Text("Continue with Google").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .waiting:
            Button {} label: { Text("Continue with Google").frame(maxWidth: .infinity) }
                .buttonStyle(FadedProminentStyle(kind: .google, tint: GlassStyle.fill(.google)))
                .disabled(true)
        case .success(let id):
            Button("Done") { onDone(id) }
                .buttonStyle(.borderedProminent)
        case .failed:
            Button("Try again", action: model.start)
                .buttonStyle(.borderedProminent)
        }
    }
}
