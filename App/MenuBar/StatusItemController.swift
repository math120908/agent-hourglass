import AppKit
import Observation
import SwiftUI
import UsageCore
import UsageCoreMac

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let themeStore: ThemeStore
    private let engine: UsageEngine
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    /// Closes the popover on clicks in other apps. A menu bar (accessory) app is often not active,
    /// so `.transient` alone misses those clicks.
    private var outsideClickMonitor: Any?
    private var lastIcon: IconState?
    private var lastTheme: Theme?
    private let addAccount: AddAccountWindowController
    private let settings: SettingsWindowController
    private let settingsBackend: EngineSettingsBackend
    private let historyWindow: HistoryWindowController
    private var menuActions = PopoverActions()
    private var makeRoot: (Theme) -> PopoverRoot = { PopoverRoot(theme: $0) { Fixtures.content() } }

    init(appState: AppState, themeStore: ThemeStore, engine: UsageEngine, radar: ResetRadarController) {
        self.appState = appState
        self.themeStore = themeStore
        self.engine = engine
        let addAccount = AddAccountWindowController(engine: engine, appState: appState)
        self.addAccount = addAccount
        settingsBackend = EngineSettingsBackend(engine: engine, appState: appState)
        settings = SettingsWindowController(
            model: SettingsModel(appState: appState, backend: settingsBackend),
            addClaude: { addAccount.show() },
            addCopilot: { addAccount.show(copilot: true) },
            addCodex: { addAccount.show(codex: true) },
            addClaudeCode: { addAccount.show(claudeCode: true) },
            addGoogle: { addAccount.show(google: true) },
            addGrok: { addAccount.show(grok: true) }
        )
        let backend = settingsBackend
        historyWindow = HistoryWindowController(engine: engine) { await backend.load().entries }
        HistorySettings.shared.store = engine.history
        HistorySettings.shared.onDelete = { [historyWindow] in historyWindow.model.load() }
        HistorySettings.shared.openHistory = { [historyWindow] in historyWindow.show() }
        super.init()
        engine.setUserInterval(minutes: settings.model.intervalMinutes)
        settings.model.reload()
        popover.behavior = .transient
        popover.delegate = self
        let useFixture = CommandLine.arguments.contains("--fixture")
        let actions = PopoverActions(
            refresh: { [engine] in engine.refresh() },
            history: { [weak self] in
                self?.popover.performClose(nil)
                self?.historyWindow.show()
            },
            settings: { [weak self] in
                self?.popover.performClose(nil)
                self?.settings.show()
            },
            addAccount: { [weak self] in
                self?.popover.performClose(nil)
                self?.addAccount.show()
            },
            signIn: { [weak self] id in
                self?.popover.performClose(nil)
                // Google has no reauth: signing in again is Add Account (same remote id upserts).
                if id.kind == .google { self?.addAccount.show(google: true); return }
                // Grok has no reauth: signing in again is Add Account (same remote id upserts).
                if id.kind == .grok { self?.addAccount.show(grok: true); return }
                self?.settings.show(tab: .accounts)
                self?.settings.model.reauth(id)
            },
            openURL: { [weak self] url in
                self?.popover.performClose(nil)
                NSWorkspace.shared.open(url)
            },
            diagnostics: { [weak self] in
                self?.popover.performClose(nil)
                self?.settings.show(tab: .about)
            },
            resize: { [weak self] height in self?.resize(to: height) }
        )
        let radar = useFixture ? Fixtures.resetRadar() : radar
        makeRoot = { [appState] theme in
            let content = useFixture ? Fixtures.content(now: Date()) : PopoverContent.live(appState)
            return PopoverRoot(
                theme: theme,
                initiallyExpanded: Set(content.accounts.map(\.id)),
                actions: actions,
                radar: radar
            ) { useFixture ? Fixtures.content(now: Date()) : PopoverContent.live(appState) }
        }
        let host = NSHostingController(rootView: makeRoot(themeStore.theme))
        host.sizingOptions = []  // contentSize is driven only by resize(to:)
        popover.contentViewController = host
        historyWindow.theme = themeStore.theme
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menuActions = actions
        observe()
    }

    func debugAddCodex() { addAccount.show(codex: true) }

    func debugAddCopilot(_ login: String) { addAccount.show(copilot: true, pick: login) }

    /// Redraws the icon only when the derived IconState or theme changes.
    private func observe() {
        let (state, theme) = withObservationTracking {
            (currentIconState(), themeStore.theme)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard state != lastIcon || theme != lastTheme else { return }
        lastIcon = state
        if theme != lastTheme, lastTheme != nil { apply(theme) }
        lastTheme = theme
        statusItem.button?.image = iconRenderer(for: theme).image(for: state)
    }

    /// Live theme switch: rebuilds the popover root and an open History window.
    private func apply(_ theme: Theme) {
        (popover.contentViewController as? NSHostingController<PopoverRoot>)?.rootView = makeRoot(theme)
        if popover.isShown { fitToContent() }
        historyWindow.theme = theme
        NSLog("theme-switch %@", theme.rawValue)
    }

    private func currentIconState() -> IconState {
        IconState.make(
            appState: appState.snapshots,
            statuses: appState.statuses,
            menuBarAccount: settings.model.menuBarAccount,
            order: appState.accounts,
            now: Date()
        )
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if StatusMenuItem.opensMenu(
            isRightMouseUp: event?.type == .rightMouseUp,
            controlHeld: event?.modifierFlags.contains(.control) ?? false
        ) {
            showMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    /// Pops the right-click menu under the icon; statusItem.menu is detached after, so left-click keeps the popover.
    private func showMenu(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender) }
        let menu = buildMenu()
        NSLog("status-menu items=%@", menu.items.map { $0.isSeparatorItem ? "---" : $0.title }.joined(separator: " | "))
        // Attach for one click so AppKit anchors it under the icon like a native status menu, then detach.
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        for spec in StatusMenuItem.layout {
            guard let spec else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: spec.title, action: #selector(menuItemChosen(_:)), keyEquivalent: spec.keyEquivalent)
            item.target = self
            item.representedObject = spec.title
            menu.addItem(item)
        }
        return menu
    }

    @objc private func menuItemChosen(_ item: NSMenuItem) {
        switch StatusMenuItem.layout.compactMap({ $0 }).first(where: { $0.title == item.title }) {
        case .refresh: menuActions.refresh()
        case .history: menuActions.history()
        case .settings: menuActions.settings()
        case .quit: NSApp.terminate(nil)
        case nil: break
        }
    }

    func debugMenu() {
        guard let b = statusItem.button else { return }
        showMenu(b)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        NotificationCenter.default.post(name: .popoverWillOpen, object: nil)
        fitToContent()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()
        logGap(button: sender, tag: "open")
    }

    /// Before show: lay the root out off-window and let its height preferences land, so resize(to:)
    /// sets contentSize from the current content (first open and every reopen, never a stale size).
    private func fitToContent() {
        guard let view = popover.contentViewController?.view else { return }
        if view.frame.height < 1 { view.frame = NSRect(x: 0, y: 0, width: 340, height: PopoverSizing.maxHeight) }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        view.layoutSubtreeIfNeeded()
    }

    /// Applies the SwiftUI-reported ideal height, capped at 600 pt. Idempotent, so a repeat report is a no-op.
    private func resize(to ideal: CGFloat) {
        let target = NSSize(width: 340, height: PopoverSizing.popoverHeight(Double(ideal)))
        guard popover.contentSize != target else { return }
        let before = popover.contentSize
        guard popover.isShown else { popover.contentSize = target; return }
        popover.animates = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            popover.contentSize = target
        }, completionHandler: { [weak self] in
            // Popover window frame settles a beat after the animation group; log once it has.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self, let button = self.statusItem.button else { return }
                self.logGap(button: button, tag: "resize \(Int(before.height))->\(Int(target.height))")
            }
        })
    }

    func debugOpen() {
        if !popover.isShown, let b = statusItem.button { togglePopover(b) }
    }

    /// Debug: `--toggle-first-card` flips the first card's expansion (used to verify live resize).
    func debugToggleFirstCard() {
        if !popover.isShown, let b = statusItem.button { togglePopover(b) }
        NotificationCenter.default.post(name: .debugToggleFirstCard, object: nil)
    }

    func popoverWillShow(_ notification: Notification) { engine.setForeground(true) }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
        engine.setForeground(false)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    private func logGap(button: NSStatusBarButton, tag: String) {
        guard ProcessInfo.processInfo.environment["CU_LOG_POPOVER_GAP"] != nil,
              let buttonWindow = button.window,
              let popWindow = popover.contentViewController?.view.window else { return }
        let b = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let p = popWindow.frame
        NSLog("popover-gap [%@] content=%@ button=%@ popover=%@ gap=%.1f", tag, NSStringFromSize(popover.contentSize), NSStringFromRect(b), NSStringFromRect(p), b.minY - p.maxY)
    }
}

extension Notification.Name {
    static let popoverWillOpen = Notification.Name("popoverWillOpen")
    static let debugToggleFirstCard = Notification.Name("debugToggleFirstCard")
}
