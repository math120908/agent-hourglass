import SwiftUI
import UsageCore

@main
struct AgentHourglassApp: App {
    @State private var themeStore = ThemeStore.appGroup()
    @State private var model = AppModel(env: UsageEnvironment.live(), displayStore: DisplaySettingsStore(defaults: AppGroup.defaults))
    @State private var showSettings = false
    @State private var addFlow: AddFlow?
    @State private var radar: ResetRadarController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let radar = ResetRadarController.live()
        #if DEBUG
        let headless = CommandLine.arguments.contains("--render")
        #else
        let headless = false
        #endif
        if !headless { radar.registerBackgroundTask() }
        _radar = State(initialValue: radar)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                model: model,
                addMenu: AnyView(AddAccountMenu(app: model, present: $addFlow)),
                onSignIn: { addFlow = AddFlow.signIn(for: $0) },
                openSettings: { showSettings = true },
            )
                .sheet(item: $addFlow) { flow in
                    AddFlowSheet(flow: flow, app: model) { id in
                        addFlow = nil
                        model.focusedAccount = id
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(model: model, display: model.displayStore, themes: themeStore, radar: radar)
                }
                .appTheme(themeStore.theme)
                .environment(\.displaySettings, model.displayStore.settings)
                .environment(\.resetRadar, radar)
                .environment(\.cardAccessory, .resetRadar)
                .task { await start() }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    guard !fixturesMode else { return }
                    Task { await model.scenePhaseChanged(phase) }
                    if phase == .active { Task { await radar.sceneBecameActive() } }
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
        if scenePhase == .active {
            await model.scenePhaseChanged(.active)
            await radar.sceneBecameActive()
        }
    }
}
