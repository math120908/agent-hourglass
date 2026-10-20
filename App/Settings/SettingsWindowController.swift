import AppKit
import SwiftUI
import UsageCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", accounts = "Accounts", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .accounts: "person.2"
        case .about: "info.circle"
        }
    }
}

/// Settings window root (spec §10.5, ≈ 520 × 420), Glass material. History tab ships in a later task.
struct SettingsRoot: View {
    @Bindable var model: SettingsModel
    @State var tab: SettingsTab = .general
    var addClaude: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .padding(.top, 14)
            .padding(.bottom, 4)
            Group {
                switch tab {
                case .general: GeneralTab(model: model)
                case .accounts: AccountsTab(model: model, addClaude: addClaude)
                case .about: AboutTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 420)
        .background(.regularMaterial)
    }
}

@MainActor
final class SettingsWindowController {
    let model: SettingsModel
    private let addClaude: () -> Void
    private var window: NSWindow?

    init(model: SettingsModel, addClaude: @escaping () -> Void) {
        self.model = model
        self.addClaude = addClaude
    }

    func show(tab: SettingsTab = .general) {
        model.reload()
        let root = SettingsRoot(model: model, tab: tab, addClaude: addClaude)
        if let window {
            (window.contentViewController as? NSHostingController<SettingsRoot>)?.rootView = root
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Claude Usage Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
