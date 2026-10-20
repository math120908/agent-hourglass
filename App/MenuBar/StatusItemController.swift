import AppKit
import Observation
import SwiftUI
import UsageCore

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let themeStore: ThemeStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var lastIcon: IconState?
    private var lastTheme: Theme?

    init(appState: AppState, themeStore: ThemeStore) {
        self.appState = appState
        self.themeStore = themeStore
        super.init()
        popover.behavior = .transient
        let useFixture = CommandLine.arguments.contains("--fixture")
        let ids = useFixture ? Fixtures.content().accounts.map(\.id) : appState.accounts
        let root = PopoverRoot(theme: themeStore.theme, initiallyExpanded: PopoverRoot.storedExpansion(ids)) { [appState] in
            useFixture ? Fixtures.content(now: Date()) : PopoverContent.live(appState)
        }
        popover.contentViewController = NSHostingController(rootView: root)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        observe()
    }

    /// Redraws the icon only when the derived IconState or theme changes.
    private func observe() {
        let (state, theme) = withObservationTracking {
            (currentIconState(), themeStore.theme)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard state != lastIcon || theme != lastTheme else { return }
        lastIcon = state
        lastTheme = theme
        statusItem.button?.image = iconRenderer(for: theme).image(for: state)
    }

    private func currentIconState() -> IconState {
        IconState.make(
            appState: appState.snapshots,
            statuses: appState.statuses,
            menuBarAccount: nil,
            order: appState.accounts,
            now: Date()
        )
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        logGap(button: sender)
    }

    private func logGap(button: NSStatusBarButton) {
        guard ProcessInfo.processInfo.environment["CU_LOG_POPOVER_GAP"] != nil,
              let buttonWindow = button.window,
              let popWindow = popover.contentViewController?.view.window else { return }
        let b = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let p = popWindow.frame
        NSLog("popover-gap button=%@ popover=%@ gap=%.1f", NSStringFromRect(b), NSStringFromRect(p), b.minY - p.maxY)
    }
}
