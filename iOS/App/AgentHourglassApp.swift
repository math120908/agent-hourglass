import SwiftUI
import UsageCore

@main
struct AgentHourglassApp: App {
    @State private var themeStore = ThemeStore.appGroup()
    @State private var model = AppModel(env: UsageEnvironment.live(), displayStore: DisplaySettingsStore(defaults: AppGroup.defaults))
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView(model: model, addMenu: AnyView(EmptyView()), onSignIn: { _ in }, openSettings: { showSettings = true })
                .environment(\.appTheme, themeStore.theme)
                .environment(\.displaySettings, model.displayStore.settings)
                .task { await start() }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if !fixturesMode { Task { await model.scenePhaseChanged(phase) } }
                }
        }
    }

    private var fixturesMode: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--fixtures")
        #else
        false
        #endif
    }

    @MainActor private func start() async {
        #if DEBUG
        if await RenderHook.runIfRequested() { return }
        let args = CommandLine.arguments
        if args.contains("--seed-demo") { try? await DemoSeed.seed(UsageEnvironment.live()) }
        if args.contains("--clear-demo") { try? await DemoSeed.clear(UsageEnvironment.live()) }
        if fixturesMode {
            model.loadFixtures()
            return
        }
        #endif
        await model.load()
        if scenePhase == .active { await model.scenePhaseChanged(.active) }
    }
}
