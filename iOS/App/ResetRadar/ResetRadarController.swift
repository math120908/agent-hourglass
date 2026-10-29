import BackgroundTasks
import os
import SwiftUI
import UIKit
import UsageCore
@preconcurrency import UserNotifications

/// Drives the Codex reset radar: checks on foreground and in a BGAppRefreshTask, posts notifications,
/// and presents the timeline row.
@MainActor
@Observable
final class ResetRadarController: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let showKey = "resetRadar.show"
    nonisolated static let notifyKey = "resetRadar.notify"
    nonisolated static let notifyCreditsKey = "resetRadar.notifyCredits"
    nonisolated static let taskID = "cc.kuoc.agent-hourglass.reset-radar"
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "ResetRadar")

    private(set) var events: [ResetEvent]
    @ObservationIgnored private let feed: ResetRadarFeed?
    @ObservationIgnored private let defaults: UserDefaults
    /// Submitting an unregistered id throws an ObjC exception, so scheduling waits for registration.
    @ObservationIgnored private var isRegistered = false
    @ObservationIgnored private let auth: NotificationAuth

    /// Notification authorization seam; tests inject a fake.
    struct NotificationAuth: Sendable {
        var status: @Sendable () async -> UNAuthorizationStatus
        var request: @Sendable () async -> Void

        static let live = NotificationAuth(
            status: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
            request: { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        )
    }

    init(
        events: [ResetEvent] = [],
        feed: ResetRadarFeed? = nil,
        defaults: UserDefaults = .standard,
        auth: NotificationAuth = .live
    ) {
        self.events = events
        self.feed = feed
        self.defaults = defaults
        self.auth = auth
        Self.registerDefaults(defaults)
        settings = ResetRadarSettings(
            show: defaults.bool(forKey: Self.showKey),
            notify: defaults.bool(forKey: Self.notifyKey),
            notifyCredits: defaults.bool(forKey: Self.notifyCreditsKey)
        )
        super.init()
        // Set before launch completes so a cold-launch notification tap is delivered.
        if feed != nil { UNUserNotificationCenter.current().delegate = self }
    }

    nonisolated static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "AgentHourglass/\(version) (+https://github.com/math120908/agent-hourglass)"
    }

    /// Live controller hitting codex-reset.com.
    static func live() -> ResetRadarController {
        let feed = ResetRadarFeed(http: HTTPClient(), storage: UserDefaultsResetRadarStorage(), userAgent: userAgent)
        return ResetRadarController(feed: feed)
    }

    nonisolated static func registerDefaults(_ defaults: UserDefaults) {
        let d = ResetRadarSettings()
        defaults.register(defaults: [showKey: d.show, notifyKey: d.notify, notifyCreditsKey: d.notifyCredits])
    }

    /// UserDefaults-backed; observable so the settings toggles and the card row update live.
    var settings: ResetRadarSettings {
        didSet {
            guard settings != oldValue else { return }
            defaults.set(settings.show, forKey: Self.showKey)
            defaults.set(settings.notify, forKey: Self.notifyKey)
            defaults.set(settings.notifyCredits, forKey: Self.notifyCreditsKey)
            if settings.notify, !oldValue.notify {
                Task { [auth] in await auth.request() }
            }
        }
    }

    // MARK: Background refresh

    /// Must run before the app finishes launching.
    func registerBackgroundTask() {
        isRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { [weak self] task in
            nonisolated(unsafe) let task = task
            Task { @MainActor in
                guard let self else { task.setTaskCompleted(success: false); return }
                let work = Task { await self.refreshNow() }
                task.expirationHandler = { work.cancel() }
                await work.value
                self.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    nonisolated static func refreshRequest(now: Date) -> BGAppRefreshTaskRequest {
        let r = BGAppRefreshTaskRequest(identifier: taskID)
        r.earliestBeginDate = now.addingTimeInterval(3600)
        return r
    }

    func scheduleBackgroundRefresh(now: Date = Date()) {
        guard isRegistered else { return }
        do { try BGTaskScheduler.shared.submit(Self.refreshRequest(now: now)) } catch {
            Self.log.info("bg refresh submit failed error=\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Foreground check (throttled to 60 s inside the feed), then re-arm the background task.
    /// `notify` defaults on, so the first prompt is asked here; a background task cannot show it.
    func sceneBecameActive() async {
        if settings.notify, await auth.status() == .notDetermined { await auth.request() }
        await refreshNow()
        scheduleBackgroundRefresh()
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

    /// Posts `events` and returns those whose request was accepted; [] when not authorized.
    /// Never prompts: this may run inside the BGAppRefreshTask.
    private func post(_ events: [ResetEvent]) async -> [ResetEvent] {
        let center = UNUserNotificationCenter.current()
        guard [.authorized, .provisional].contains(await auth.status()) else {
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
        let posix = Locale(identifier: "en_US_POSIX")
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.locale = posix
        fmt.dateFormat = "MMM d HH:mm"
        let dayIn = DateFormatter()
        dayIn.locale = posix
        dayIn.timeZone = TimeZone(identifier: "UTC")
        dayIn.dateFormat = "yyyy-MM-dd"
        let dayOut = DateFormatter()
        dayOut.locale = posix
        dayOut.timeZone = dayIn.timeZone
        dayOut.dateFormat = "MMM d"
        return events.map { e in
            let when = e.at.map(fmt.string(from:)) ?? dayIn.date(from: e.day).map(dayOut.string(from:)) ?? e.day
            return Entry(
                id: e.id,
                isCredits: e.kind == .credits,
                confirmed: e.confirmed,
                meta: when + (e.confirmed ? " | confirmed" : ""),
                summary: e.summary,
                url: e.url
            )
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
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
}
