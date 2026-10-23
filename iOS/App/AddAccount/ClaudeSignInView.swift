import SwiftUI
import UIKit
import UsageCore

/// Claude sign-in as a 3-step checklist: open claude.ai in an ephemeral auth session, copy the
/// code there, paste it here. Only the system `PasteButton` (or the user, via the field) ever
/// reads the pasteboard; the app checks `hasStrings` alone.
struct ClaudeSignInView: View {
    let model: ClaudeSignInModel
    let onDone: (AccountID) -> Void

    @State private var form: ClaudeSignInForm
    @State private var browser = PasteBrowser()
    @State private var exchange: Task<Void, Never>?
    @State private var debounce: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 20

    init(model: ClaudeSignInModel, onDone: @escaping (AccountID) -> Void) {
        self.init(model: model, form: ClaudeSignInForm(), onDone: onDone)
    }

    /// Snapshot hook: a fixed form (text, opened, hasStrings).
    init(model: ClaudeSignInModel, form: ClaudeSignInForm, onDone: @escaping (AccountID) -> Void) {
        self.model = model
        self.onDone = onDone
        _form = State(initialValue: form)
    }

    private var state: ClaudeSignInModel.State { model.state }
    private var steps: [ClaudeSignInForm.Step] { form.steps(state) }
    private var isGlass: Bool { theme == .glass }
    private var isSuccess: Bool { if case .success = state { true } else { false } }
    private var isFinished: Bool {
        switch state {
        case .success, .failed: true
        case .browsing, .exchanging: false
        }
    }

    var body: some View {
        // Scrolls only when it must (AX type sizes); otherwise everything is pinned top.
        ScrollView {
            VStack(spacing: 0) {
                header
                secondary(Text("Sign in on claude.ai, then paste the code here.").font(.subheadline))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                card.padding(.top, 24)
                result.padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { AppBackdrop().ignoresSafeArea() }
        .tint(GlassStyle.claude)
        .animation(reduceMotion ? nil : .snappy, value: steps)
        // Cancel stays in every state (as on the Codex sheet) so the layout never jumps.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Provider accent on every theme, in its readable variant (the stock accent is ~3:1 on
                // the light toolbar pill).
                Button("Cancel") { dismiss() }.tint(SheetTone.accentText(.claude, scheme))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, form.opened, form.text.isEmpty, state == .browsing {
                form.hasStrings = UIPasteboard.general.hasStrings
            }
        }
        .onChange(of: form.text) { _, _ in edited() }
        .onChange(of: state) { _, s in
            if case .success = s { AccessibilityNotification.Announcement("Added").post() }
        }
        .onDisappear {
            exchange?.cancel()
            debounce?.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIcon(kind: .claude, size: markSize)
                .foregroundStyle(GlassStyle.claude)
                .accessibilityHidden(true)
            Text("Add Claude account").font(.headline)
        }
        .padding(.top, 24)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Steps card

    @ViewBuilder private var card: some View {
        let rows = VStack(spacing: 0) {
            row(1, "Open sign-in page", combine: true) { openControl }
            divider
            row(2, "Sign in and copy the code", combine: true) { EmptyView() }
            divider
            row(3, "Paste the code", combine: false) { pasteControl }
            if isFinished {
                divider
                outcome.padding(14)
            }
        }
        rows.sheetCard()
    }

    /// Success / failure line, on the card so the status glyph keeps its contrast.
    @ViewBuilder private var outcome: some View {
        switch state {
        case .success:
            SheetStatus(text: "Added", systemImage: "checkmark.circle.fill", tint: SheetTone.success(scheme))
        case .failed(let message):
            SheetStatus(
                text: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: SheetTone.criticalGlyph(scheme),
                font: .subheadline,
            )
        case .browsing, .exchanging:
            EmptyView()
        }
    }

    @ViewBuilder private var divider: some View {
        if isGlass {
            GlassDivider()
        } else {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
        }
    }

    private func row<C: View>(_ n: Int, _ label: String, combine: Bool, @ViewBuilder control: () -> C) -> some View {
        let step = steps[n - 1]
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            StepIndicator(number: n, step: step, glass: isGlass, scheme: scheme)
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    switch step {
                    case .todo: Text(label).font(.body).foregroundStyle(SheetTone.secondary(scheme, glass: isGlass))
                    case .current: Text(label).font(.body.weight(.semibold))
                    case .done: Text(label).font(.body)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)
                control()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minHeight: 56)
        .accessibilityElement(children: combine ? .combine : .contain)
    }

    @ViewBuilder private var openControl: some View {
        if !isSuccess {
            let label = Label("Open claude.ai", systemImage: "arrow.up.forward.app")
            Group {
                if steps[0] == .current {
                    Button(action: openSignIn) { label }.buttonStyle(.borderedProminent)
                } else {
                    Button(action: openSignIn) { label }
                        .quietBordered(.claude, scheme: scheme, glass: isGlass)
                }
            }
            .buttonBorderShape(.capsule)
            .disabled(state != .browsing)
        }
    }

    @ViewBuilder private var pasteControl: some View {
        if state == .browsing || state == .exchanging {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            VStack(alignment: .leading, spacing: 6) {
                layout {
                    codeField
                    pasteButton
                }
                if state == .browsing, form.showsInvalid, form.isInvalid {
                    invalidCaption
                }
            }
            .disabled(state == .exchanging)
        }
    }

    /// Masked like a password field: the user sees that the code landed, nobody reads it. Out of
    /// focus the dots are drawn here (the secure field itself is blank in captures and snapshots);
    /// a tap still lands on the secure field underneath.
    private var codeField: some View {
        let masked = !fieldFocused && !form.text.isEmpty
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                SecureField("Code", text: $form.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("Code")
                    .opacity(masked ? 0 : 1)
                if masked {
                    // As many dots as fit (max 16), never an ellipsis: at AX sizes fewer dots show.
                    ViewThatFits(in: .horizontal) {
                        ForEach([16, 12, 8, 6, 4], id: \.self) { n in
                            Text(String(repeating: "\u{2022}", count: min(form.text.count, n)))
                                .font(.body.monospaced())
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .opacity(state == .exchanging ? 0.6 : 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            validationGlyph
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    /// On Glass dark a red text tone tops out near 4.3:1 on the grey card, so the text stays
    /// near-white (4.8:1) and a red glyph carries the hue.
    @ViewBuilder private var invalidCaption: some View {
        let text = Text("That code isn't complete").foregroundStyle(SheetTone.criticalText(scheme, glass: isGlass))
        Group {
            if isGlass, scheme == .dark {
                Label {
                    text
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SheetTone.criticalGlyph(scheme))
                }
                .labelStyle(.titleAndIcon)
            } else {
                text
            }
        }
        .font(.caption)
    }

    @ViewBuilder private var validationGlyph: some View {
        if form.parsable {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SheetTone.success(scheme))
                .accessibilityLabel("Code complete")
        } else if form.isInvalid {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SheetTone.criticalGlyph(scheme))
                .accessibilityLabel("Code incomplete")
        }
    }

    @ViewBuilder private var pasteButton: some View {
        let button = PasteButton(payloadType: String.self) { items in pasted(items.first ?? "") }
        Group {
            if form.pasteProminent(state) {
                button.labelStyle(.titleAndIcon)
            } else {
                button.labelStyle(.iconOnly)
            }
        }
        .buttonBorderShape(.capsule)
        .tint(GlassStyle.claude)
        // UIPasteControl ignores `.controlSize` and draws a 34 pt capsule centered in its frame:
        // a 44 pt frame gives the touch target, a same-tint capsule behind it the 44 pt look.
        .frame(minWidth: 34, minHeight: 44)
        .padding(.horizontal, 5)
        // Drawn whenever the button shows, so the 44 pt size holds while exchanging; faded there
        // to sit with the system disabled capsule.
        .background { Capsule().fill(GlassStyle.claude).opacity(state == .browsing ? 1 : 0.5) }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Primary / result

    @ViewBuilder private var result: some View {
        switch state {
        case .browsing:
            let label = Text("Continue").frame(maxWidth: .infinity)
            if form.canContinue(state) {
                Button(action: submit) { label }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button(action: submit) { label }
                    .buttonStyle(FadedProminentStyle(tint: GlassStyle.claude))
                    .disabled(true)
            }
        case .exchanging:
            HStack(spacing: 8) {
                ProgressView().tint(isGlass && scheme == .dark ? .white : nil)
                secondary(Text("Signing in").font(.subheadline))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityElement(children: .combine)
        case .success(let id):
            Button("Done") { onDone(id) }
                .buttonStyle(.borderedProminent)
        case .failed:
            Button("Try again", action: tryAgain)
                .buttonStyle(.borderedProminent)
        }
    }

    private func secondary(_ text: Text) -> some View {
        text.foregroundStyle(SheetTone.secondary(scheme, glass: isGlass))
    }

    // MARK: Actions

    private func openSignIn() {
        browser.open(model.authorizeURL) {
            form.returned(hasStrings: UIPasteboard.general.hasStrings)
            fieldFocused = true
        }
    }

    private func pasted(_ s: String) {
        debounce?.cancel()
        form.pasted(s)
    }

    private func edited() {
        debounce?.cancel()
        guard form.edited() else { return }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            form.debounceElapsed()
        }
    }

    private func submit() {
        guard form.canContinue(state) else {
            if form.isInvalid {
                debounce?.cancel()
                form.showsInvalid = true
            }
            return
        }
        fieldFocused = false
        let text = form.text
        exchange = Task { await model.receivePasted(text) }
    }

    private func tryAgain() {
        debounce?.cancel()
        form.reset()
        model.restart()
    }
}

/// 28 pt step marker: number in a soft disc (todo), Claude ring (current), filled check (done).
private struct StepIndicator: View {
    let number: Int
    let step: ClaudeSignInForm.Step
    let glass: Bool
    let scheme: ColorScheme

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        ZStack {
            switch step {
            case .todo:
                if glass {
                    Circle().fill(Color.primary.opacity(0.10))
                    Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(SheetTone.secondary(scheme, glass: true))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 2)
                    Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(SheetTone.secondary(scheme, glass: false))
                }
            case .current:
                // Lifted (dark) / deepened (light) ring clears 3:1 on every card; the number stays primary.
                Circle().strokeBorder(SheetTone.claude(scheme), lineWidth: 2.5)
                Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            case .done:
                Circle().fill(GlassStyle.claude)
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Step \(number), \(phrase)")
    }

    private var phrase: String {
        switch step {
        case .todo: "not started"
        case .current: "current"
        case .done: "done"
        }
    }
}
