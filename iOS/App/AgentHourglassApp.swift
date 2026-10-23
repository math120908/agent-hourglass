import SwiftUI
import UsageCore

@main
struct AgentHourglassApp: App {
    @State private var themeStore = ThemeStore.appGroup()
    @State private var lines: [ShellStatusLine] = []
    @State private var settings = DisplaySettings.default
    @Environment(\.scenePhase) private var scenePhase
    private let env = UsageEnvironment.live()

    var body: some Scene {
        WindowGroup {
            AccountListView(lines: lines, theme: themeStore.theme, showRemaining: settings.showRemaining)
                .task { await refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await refresh() } }
                }
        }
    }

    @MainActor private func refresh() async {
        #if DEBUG
        if await RenderHook.runIfRequested() { return }
        let args = CommandLine.arguments
        if args.contains("--seed-demo") { try? await DemoSeed.seed(env) }
        if args.contains("--clear-demo") { try? await DemoSeed.clear(env) }
        #endif
        settings = DisplaySettings.load(from: AppGroup.defaults)
        lines = await ShellStatus.load(env, now: .now)
        ShellStatus.log(lines, process: "app")
        WidgetReloader.reloadAll()
    }
}
