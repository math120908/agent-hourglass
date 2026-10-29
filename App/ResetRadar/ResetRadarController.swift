import AppKit
import os
import SwiftUI
import UsageCore
@preconcurrency import UserNotifications

/// Drives the Codex reset radar: hourly feed check, notifications, and row presentation.
@MainActor
@Observable
final class ResetRadarController: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let showKey = "resetRadar.show"
    nonisolated static let notifyKey = "resetRadar.notify"
    nonisolated static let notifyCreditsKey = "resetRadar.notifyCredits"
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "ResetRadar")

    private(set) var events: [ResetEvent]
    @ObservationIgnored private let feed: ResetRadarFeed?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(events: [ResetEvent] = [], feed: ResetRadarFeed? = nil) {
        self.events = events
        self.feed = feed
        super.init()
        Self.registerDefaults()
        // Set before launch completes so a cold-launch notification tap is delivered.
        if feed != nil { UNUserNotificationCenter.current().delegate = self }
    }

    /// Live controller hitting codex-reset.com.
    static func live() -> ResetRadarController {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let ua = "AgentHourglass/\(version) (+https://github.com/math120908/agent-hourglass)"
        let feed = ResetRadarFeed(http: HTTPClient(), storage: UserDefaultsResetRadarStorage(), userAgent: ua)
        return ResetRadarController(feed: feed)
    }

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        let d = ResetRadarSettings()
        defaults.register(defaults: [showKey: d.show, notifyKey: d.notify, notifyCreditsKey: d.notifyCredits])
    }

    var settings: ResetRadarSettings {
        let d = UserDefaults.standard
        return ResetRadarSettings(show: d.bool(forKey: Self.showKey), notify: d.bool(forKey: Self.notifyKey), notifyCredits: d.bool(forKey: Self.notifyCreditsKey))
    }

    func start() {
        guard loop == nil, feed != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let self else { return }
                    await self.refreshNow()
                }
                try? await Task.sleep(for: ResetRadarFeed.interval)
            }
        }
    }

    func refreshNow() async {
        guard let feed else { return }
        let settings = settings
        let toNotify = await feed.check(settings: settings)
        events = await feed.events
        guard settings.notify, !toNotify.isEmpty else { return }
        let posted = await post(toNotify)
        await feed.markNotified(posted)
    }

    /// Posts `events` and returns those whose request was accepted; [] when authorization is denied.
    private func post(_ events: [ResetEvent]) async -> [ResetEvent] {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            Self.log.info("notification authorization not granted")
            return []
        }
        var posted: [ResetEvent] = []
        for e in events {
            let content = UNMutableNotificationContent()
            content.title = e.kind == .credits ? "Codex credits event" : "Codex usage reset 🎉"
            content.body = Self.truncated(e.summary, 140)
            if let url = e.url { content.userInfo = ["url": url.absoluteString] }
            do {
                try await center.add(UNNotificationRequest(identifier: "reset-radar.\(e.dedupeKey)", content: content, trigger: nil))
                posted.append(e)
            } catch {
                Self.log.error("notification post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return posted
    }

    nonisolated static func truncated(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }

    // MARK: Presentation

    struct Entry: Identifiable {
        let id: String
        let isCredits: Bool
        let confirmed: Bool
        let meta: String
        let summary: String
        let url: URL?
    }

    func caption(now: Date) -> String? { ResetRadarLogic.lastResetCaption(events, now: now) }

    func entries(calendar: Calendar) -> [Entry] {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM d HH:mm"
        let dayIn = DateFormatter()
        dayIn.locale = fmt.locale
        dayIn.timeZone = TimeZone(identifier: "UTC")
        dayIn.dateFormat = "yyyy-MM-dd"
        let dayOut = DateFormatter()
        dayOut.locale = fmt.locale
        dayOut.timeZone = dayIn.timeZone
        dayOut.dateFormat = "MMM d"
        return events.map { e in
            let when = e.at.map(fmt.string(from:)) ?? dayIn.date(from: e.day).map(dayOut.string(from:)) ?? e.day
            return Entry(id: e.id, isCredits: e.kind == .credits, confirmed: e.confirmed,
                         meta: when + (e.confirmed ? " | confirmed" : ""), summary: e.summary, url: e.url)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension EnvironmentValues {
    @Entry var resetRadar: ResetRadarController?
    /// Snapshot rendering only: start the radar timeline expanded.
    @Entry var resetRadarInitiallyOpen = false
}
