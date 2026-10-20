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
        .frame(width: 380)
        .background(.regularMaterial)
    }

    private var providerStep: some View {
        HStack(spacing: 10) {
            bigButton("Claude", "sparkle", enabled: true) { model.step = .claudeEmail }
            bigButton("Copilot", "chevron.left.forwardslash.chevron.right", enabled: true) { model.loadLogins() }
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
        case .idle, .waiting:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.isCopilot ? "Adding Copilot account…" : "Waiting for sign-in in your browser…").font(.system(size: 12))
                }
                if !model.isCopilot { HStack {
                    Button("Didn't open? Copy link") { model.copyLink() }.buttonStyle(.link)
                    Spacer()
                    Button("Cancel") { model.cancel() }
                } }
            }
        case let .success(id):
            VStack(alignment: .leading, spacing: 10) {
                Label(id.kind == .copilot ? "Added" : "Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(id.rawValue.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id.rawValue)
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

    func show(copilot: Bool = false, pick: String? = nil) {
        if let window, model?.state.isWaiting == true || window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = AddAccountModel(engine: engine)
        self.model = model
        if let pick { model.addCopilot(pick) } else if copilot { model.loadLogins() }
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
