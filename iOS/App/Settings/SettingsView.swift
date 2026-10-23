import SwiftUI
import UIKit
import UsageCore
import WidgetKit

/// Settings screen (spec §10.5): Accounts, Appearance, Refresh, About. No section footers.
struct SettingsView: View {
    let model: AppModel
    @Bindable var display: DisplaySettingsStore
    @Bindable var themes: ThemeStore
    @Environment(\.appTheme) private var theme
    @State private var pendingRemove: AccountEntry?
    @State private var editMode: EditMode

    init(model: AppModel, display: DisplaySettingsStore, themes: ThemeStore) {
        self.init(model: model, display: display, themes: themes, editMode: .inactive)
    }

    init(model: AppModel, display: DisplaySettingsStore, themes: ThemeStore, editMode: EditMode) {
        self.model = model
        self.display = display
        self.themes = themes
        _editMode = State(initialValue: editMode)
    }

    var body: some View {
        Form {
            AccountsSection(model: model, rowBackground: rowBackground, pendingRemove: $pendingRemove)
            Section("Appearance") {
                Picker("Theme", selection: $themes.theme) {
                    Text("Glass").tag(Theme.glass)
                    Text("Instrument").tag(Theme.instrument)
                }
                .listRowBackground(rowBackground)
                Toggle("Show remaining", isOn: $display.settings.showRemaining).listRowBackground(rowBackground)
                Picker("Reset time", selection: $display.settings.resetStyle) {
                    Text("Clock").tag(ResetStyle.clock)
                    Text("Countdown").tag(ResetStyle.countdown)
                }
                .listRowBackground(rowBackground)
                Picker("24-hour time", selection: $display.settings.hour24) {
                    Text("System").tag(Hour24.system)
                    Text("On").tag(Hour24.on)
                    Text("Off").tag(Hour24.off)
                }
                .listRowBackground(rowBackground)
            }
            Section("Refresh") {
                Picker("Refresh every", selection: refreshMinutes) {
                    ForEach(DisplaySettings.allowedRefreshMinutes, id: \.self) { Text("\($0) min").tag($0) }
                }
                .listRowBackground(rowBackground)
            }
            Section {
                NavigationLink("About") { AboutView(diagnostics: model.diagnosticsReport) }
                    .listRowBackground(rowBackground)
            }
        }
        .scrollContentBackground(theme == .instrument ? .hidden : .automatic)
        .background(theme == .instrument ? Self.instrumentBackground : Color.clear)
        .navigationTitle("Settings")
        .toolbar { EditButton() }
        .environment(\.editMode, $editMode)
        .onChange(of: themes.theme) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var refreshMinutes: Binding<Int> {
        Binding(
            get: { display.settings.refreshMinutes },
            set: { m in Task { await model.setRefreshMinutes(m) } }
        )
    }

    private var rowBackground: Color? {
        theme == .instrument ? Self.instrumentRow : nil
    }

    private static let instrumentBackground = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.07, alpha: 1) : UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
    })
    private static let instrumentRow = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
    })
}
