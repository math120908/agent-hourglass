import SwiftUI
import UIKit
import UsageCore

/// Codex sign-in as a 3-step checklist: copy the code, enter it on auth.openai.com, come back
/// while the poll finishes. Same skeleton as `ClaudeSignInView`.
struct DeviceCodeSheet: View {
    let model: DeviceCodeFlowModel
    let onDone: (AccountID) -> Void

    @State private var form: CodexSignInForm
    /// Clock for the step 3 line; bumped on return and when the still-waiting hint is due.
    @State private var now = Date()

    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DeviceCodeFlowModel, onDone: @escaping (AccountID) -> Void) {
        self.init(model: model, form: CodexSignInForm(), onDone: onDone)
    }

    /// Snapshot hook: a fixed form (copied, opened, returnedAt).
    init(model: DeviceCodeFlowModel, form: CodexSignInForm, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.onDone = onDone
        _form = State(initialValue: form)
    }

    private var state: DeviceCodeFlowModel.State { model.state }
    private var steps: [SignInStep] { form.steps(state) }
    private var waitLine: CodexSignInForm.WaitLine? { form.waitLine(state, now: now) }
    private var isGlass: Bool { theme == .glass }
    private var prompt: DeviceCodePrompt? { if case .waiting(let p) = state { p } else { nil } }
    private var isFinished: Bool {
        switch state {
        case .expired, .failed, .success: true
        case .starting, .waiting: false
        }
    }

    var body: some View {
        SignInSheetLayout(kind: .codex, title: "Add \(model.title) account", lead: "Enter this code on auth.openai.com, then come back here.") {
            card
        } primary: {
            primary
        }
        .animation(reduceMotion ? nil : .snappy, value: steps)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            form.cameBack(at: now, state: state)
            model.foreground()
        }
        .task(id: form.stillWaitingAt) {
            guard let at = form.stillWaitingAt else { return }
            let delay = at.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            now = Date()
        }
        .onChange(of: waitLine) { _, line in
            if line == .stillWaiting { AccessibilityNotification.Announcement(Self.stillWaiting).post() }
        }
        .onChange(of: state) { _, s in
            if case .success = s { AccessibilityNotification.Announcement("Added").post() }
        }
        .onDisappear { model.cancel() }
    }

    private static let finishing = "Finishing sign-in. This can take up to 15 seconds."
    private static let stillWaiting = "Still waiting. If the browser didn't say signed in, open it again."

    // MARK: Steps card

    private var card: some View {
        VStack(spacing: 0) {
            SignInStepRow(number: 1, label: "Copy the code", step: steps[0], kind: .codex) { copyControl }
            SignInDivider()
            SignInStepRow(number: 2, label: "Sign in and enter the code", step: steps[1], kind: .codex) { openControl }
            SignInDivider()
            SignInStepRow(number: 3, label: "Come back here and wait", step: steps[2], kind: .codex) { waitControl }
            if isFinished {
                SignInDivider()
                outcome.padding(14)
            }
        }
    }

    @ViewBuilder private var copyControl: some View {
        if !isFinished {
            VStack(alignment: .leading, spacing: 10) {
                code
                copyButton.buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder private var code: some View {
        if let prompt {
            // Useless without the device_auth_id and dead in 15 min, so not privacy-sensitive.
            Text(prompt.userCode)
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .kerning(1)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(waitLine == nil ? 1 : 0.7)
                .accessibilityLabel(Text(prompt.userCode).speechSpellsOutCharacters())
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 184, height: 34)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var copyButton: some View {
        let copyLabel = Label("Copy", systemImage: "doc.on.doc")
        if prompt == nil {
            Button {} label: { copyLabel }
                .buttonStyle(FadedProminentStyle(kind: .codex, tint: GlassStyle.codexFill, compact: true))
                .disabled(true)
        } else if form.copyProminent(state) {
            Button(action: copy) { copyLabel }.buttonStyle(.borderedProminent)
        } else if form.copied {
            Button(action: copy) { Label("Copied", systemImage: "checkmark") }
                .quietBordered(.codex, scheme: scheme, glass: isGlass)
        } else {
            Button(action: copy) { copyLabel }
                .quietBordered(.codex, scheme: scheme, glass: isGlass)
        }
    }

    /// Re-open stays available after the return, for a browser that never said signed in.
    @ViewBuilder private var openControl: some View {
        if !isFinished {
            let label = Label("Open auth.openai.com", systemImage: "arrow.up.forward.app")
            Group {
                if form.openProminent(state) {
                    Button(action: open) { label }.buttonStyle(.borderedProminent)
                } else {
                    Button(action: open) { label }
                        .quietBordered(.codex, scheme: scheme, glass: isGlass)
                }
            }
            .buttonBorderShape(.capsule)
            .disabled(prompt == nil)
        }
    }

    @ViewBuilder private var waitControl: some View {
        if let waitLine {
            HStack(spacing: 8) {
                ProgressView().tint(isGlass && scheme == .dark ? .white : nil)
                Text(waitLine == .finishing ? Self.finishing : Self.stillWaiting)
                    .font(.subheadline)
                    .foregroundStyle(SheetTone.secondary(scheme, glass: isGlass))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Outcome line on the card so the status glyph keeps its contrast.
    @ViewBuilder private var outcome: some View {
        switch state {
        case .success:
            SheetStatus(text: "Added", systemImage: "checkmark.circle.fill", tint: SheetTone.success(scheme))
        case .expired:
            SheetStatus(text: "That code expired", systemImage: "clock.badge.exclamationmark", tint: SheetTone.criticalGlyph(scheme))
        case .failed(let message):
            SheetStatus(
                text: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: SheetTone.criticalGlyph(scheme),
                font: .subheadline,
            )
        case .starting, .waiting:
            EmptyView()
        }
    }

    // MARK: Primary

    @ViewBuilder private var primary: some View {
        switch state {
        case .success(let id):
            Button("Done") { onDone(id) }.buttonStyle(.borderedProminent)
        case .expired:
            Button("Get a new code", action: restart).buttonStyle(.borderedProminent)
        case .failed:
            Button("Try again", action: restart).buttonStyle(.borderedProminent)
        case .starting, .waiting:
            EmptyView()
        }
    }

    // MARK: Actions

    private func copy() {
        guard let prompt else { return }
        UIPasteboard.general.string = prompt.userCode
        form.copy()
    }

    private func open() {
        guard let prompt else { return }
        form.open()
        openURL(prompt.verificationURL)
    }

    private func restart() {
        form.reset()
        model.restart()
    }
}
