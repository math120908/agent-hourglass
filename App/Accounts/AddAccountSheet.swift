import AppKit
import SwiftUI
import UsageCore

/// Add Account sheet (spec §10.6), Glass style.
struct AddAccountSheet: View {
    @Bindable var model: AddAccountModel
    var appState: AppState
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add account").font(.system(size: 15, weight: .semibold))
            switch model.step {
            case .provider: providerStep
            case .claudeEmail: emailStep
            case .copilotPick: copilotStep
            case .flow: flowStep
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(.regularMaterial)
    }

    private var providerStep: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Claude account (sign in)") { model.step = .claudeEmail }
                Button("Claude Code (local, read-only)") { model.addClaudeCodeLocal() }
            } label: {
                Label("Claude", systemImage: "sparkle")
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: .infinity, minHeight: 44)
            bigButton("Copilot", "chevron.left.forwardslash.chevron.right", enabled: true) { model.loadLogins() }
            bigButton("Codex", "terminal", enabled: true) { model.addCodex() }
            bigButton("Google AI", "g.circle", enabled: true) { model.addGoogle() }
            bigButton("Grok", "bolt.horizontal", enabled: true) { model.addGrok() }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Email (optional)", text: $model.email)
                .textFieldStyle(.roundedBorder)
            Text("Tip: to add a second account, finish sign-in in a private browser window so the current session isn't reused.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Back") { model.step = .provider }
                Spacer()
                Button("Continue in browser") { model.start() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var copilotStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a GitHub login from gh").font(.system(size: 12)).foregroundStyle(.secondary)
            if let logins = model.logins {
                if logins.isEmpty {
                    Label("Install gh and run `gh auth login`", systemImage: "terminal")
                        .font(.system(size: 12))
                } else {
                    ForEach(logins, id: \.self) { login in
                        Button { model.addCopilot(login) } label: {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                Text(login).font(.system(size: 13, design: .monospaced))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading gh logins…").font(.system(size: 12)) }
            }
            Text("Uses your existing gh login. Nothing is saved to the Keychain.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Back") { model.step = .provider }
                Spacer()
                Button("Refresh list") { model.loadLogins() }
            }
        }
    }

    @ViewBuilder private var flowStep: some View {
        switch model.state {
        case .idle where model.isGrok, .waiting where model.isGrok:
            grokCodeStep
        case .idle, .waiting:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.isClaudeCode ? "Adding Claude Code (local)…" : model.isCodex ? "Adding Codex account…" : model.isCopilot ? "Adding Copilot account…" : model.isGoogle ? "Waiting for Google sign-in in your browser…" : "Waiting for sign-in in your browser…").font(.system(size: 12))
                }
                if !model.isCopilot && !model.isCodex && !model.isClaudeCode { HStack {
                    Button("Didn't open? Copy link") { model.copyLink() }.buttonStyle(.link)
                    Spacer()
                    Button("Cancel") { model.cancel() }
                } }
            }
        case let .success(id):
            VStack(alignment: .leading, spacing: 10) {
                Label(id.kind != .claude ? "Added" : "Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                // Codex, Google, and Grok ids carry a remote account id: never shown.
                Text(id.isClaudeCodeLocal ? "Claude Code (local, read-only). macOS will ask once for Keychain access: click Always Allow." : id.kind == .codex ? "Codex CLI login" : id.kind == .google ? "Google AI (Antigravity quota)" : id.kind == .grok ? "Grok (SuperGrok weekly pool)" : id.rawValue.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id.rawValue)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                if let snap = appState.snapshots[id] {
                    ForEach(Array(snap.meters.enumerated()), id: \.offset) { _, m in
                        HStack {
                            Text(m.label).font(.system(size: 12))
                            Spacer()
                            Text(m.percentUsed.map { String(format: "%.0f%%", $0) } ?? "–")
                                .font(.system(size: 12).monospacedDigit())
                        }
                    }
                } else {
                    Text("Fetching first snapshot…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.defaultAction) }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(GlassStyle.warning)
                HStack {
                    Button("Close", action: close)
                    Spacer()
                    Button("Retry") { model.retry() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// Grok device code: the user types this code on x.ai, so there is no link to copy.
    @ViewBuilder private var grokCodeStep: some View {
        if let p = model.devicePrompt {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter this code on x.ai").font(.system(size: 12))
                Text(p.userCode)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Copy code") { model.copyCode() }
                    Button("Open x.ai again") { AddAccountModel.open(p.verificationURL) }
                    Spacer()
                    Button("Cancel") { model.cancel() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Getting a code…").font(.system(size: 12))
                }
                HStack { Spacer(); Button("Cancel") { model.cancel() } }
            }
        }
    }

    private func bigButton(
        _ title: String,
        _ symbol: String,
        enabled: Bool,
        note: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22))
                Text(title).font(.system(size: 13, weight: .medium))
                if let note { Text(note).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Hosts the sheet in a single reusable window.
@MainActor
final class AddAccountWindowController {
    private let engine: UsageEngine
    private let appState: AppState
    private var window: NSWindow?
    private var model: AddAccountModel?

    init(engine: UsageEngine, appState: AppState) {
        self.engine = engine
        self.appState = appState
    }

    func show(copilot: Bool = false, pick: String? = nil, codex: Bool = false, claudeCode: Bool = false, google: Bool = false, grok: Bool = false) {
        if let window, model?.state.isWaiting == true || window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = AddAccountModel(engine: engine)
        self.model = model
        if claudeCode { model.addClaudeCodeLocal() } else if google { model.addGoogle() } else if grok { model.addGrok() } else if codex { model.addCodex() } else if let pick { model.addCopilot(pick) } else if copilot { model.loadLogins() }
        let view = AddAccountSheet(model: model, appState: appState) { [weak self] in self?.window?.close() }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Add Account"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
