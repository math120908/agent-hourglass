import Foundation
import UsageCore
import WidgetKit
import os

struct UsageTimelineProvider: AppIntentTimelineProvider {
    typealias Fetch = @Sendable (AccountID) async -> (UsageSnapshot?, AccountStatus?)

    var fetch: Fetch = UsageTimelineProvider.liveFetch
    var cacheRead: @Sendable (AccountID) -> UsageSnapshot? = { UsageEnvironment.live().shared.cache.read($0) }
    var loadEntries: @Sendable () async -> [AccountEntry] = { await AccountCatalog.loadEntries() }
    var loadSettings: @Sendable () -> (DisplaySettings, Theme) = {
        (DisplaySettings.load(from: AppGroup.defaults), Theme.current(in: AppGroup.defaults))
    }
    var now: @Sendable () -> Date = { Date() }
    var timeout: TimeInterval = 20

    static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Widget")

    /// Shared lock, backoff and minimumInterval all live behind `makeClient`.
    static let liveFetch: Fetch = { id in
        let env = UsageEnvironment.live()
        let kind = id.kind.map { "\($0)" } ?? "none"
        guard let client = env.makeClient(id) else {
            log.info("fetch kind=\(kind, privacy: .public) outcome=unsupported")
            return (env.shared.cache.read(id), nil)
        }
        switch await client.fetch() {
        case .success(let s):
            log.info("fetch kind=\(kind, privacy: .public) outcome=success")
            return (s, .fresh)
        case .failure(let st):
            log.info("fetch kind=\(kind, privacy: .public) outcome=failure \(String(describing: st), privacy: .public)")
            return (env.shared.cache.read(id), st)
        }
    }

    func placeholder(in context: Context) -> UsageEntry { Self.placeholderEntry(now: now()) }

    func snapshot(for configuration: SelectAccountMetersIntent, in context: Context) async -> UsageEntry {
        let entries = await loadEntries()
        guard let account = AccountCatalog.resolve(configuration.account?.id, in: entries),
              let cached = cacheRead(account.id) else { return placeholder(in: context) }
        let input = makeInput(account: account, snapshot: cached, status: nil, intent: configuration, family: Self.kind(context.family))
        return TimelineBuilder.entry(input, at: now())
    }

    func timeline(for configuration: SelectAccountMetersIntent, in context: Context) async -> Timeline<UsageEntry> {
        let t = await makeTimeline(intent: configuration, family: Self.kind(context.family))
        return Timeline(entries: t.entries, policy: .after(t.reload))
    }

    /// Testable core of `timeline(for:in:)`.
    func makeTimeline(intent: SelectAccountMetersIntent, family: WidgetFamilyKind) async -> (entries: [UsageEntry], reload: Date) {
        let entries = await loadEntries()
        guard let account = AccountCatalog.resolve(intent.account?.id, in: entries) else {
            let t = now()
            let input = makeInput(account: nil, snapshot: nil, status: nil, intent: intent, family: family)
            return ([TimelineBuilder.entry(input, at: t)], TimelinePlan.reloadDate(now: t))
        }
        let (snapshot, live) = await fetchWithTimeout(account.id)
        // No live status (signed out, unsupported, timeout): trust the persisted registry status.
        let status = live ?? Self.persistedStatus(account.status)
        let t = now()
        let input = makeInput(account: account, snapshot: snapshot, status: status, intent: intent, family: family)
        return (TimelineBuilder.entries(input, now: t), TimelinePlan.reloadDate(now: t))
    }

    /// Races `fetch` against `timeout`; on timeout returns the cache with no status.
    func fetchWithTimeout(_ id: AccountID) async -> (UsageSnapshot?, AccountStatus?) {
        let fetch = self.fetch, timeout = self.timeout, cacheRead = self.cacheRead
        let once = ResumeOnce<(UsageSnapshot?, AccountStatus?)>()
        return await withCheckedContinuation { cont in
            once.set(cont)
            let timer = TimerBox()
            let work = Task {
                if once.resume(await fetch(id)) { timer.cancel() }
            }
            timer.set(Task {
                try? await Task.sleep(for: .seconds(timeout))
                if once.resume((cacheRead(id), nil)) {
                    work.cancel()
                    Self.log.info("fetch kind=\(id.kind.map { "\($0)" } ?? "none", privacy: .public) outcome=timeout")
                }
            })
        }
    }

    private func makeInput(account: AccountEntry?, snapshot: UsageSnapshot?, status: AccountStatus?, intent: SelectAccountMetersIntent, family: WidgetFamilyKind) -> TimelineInput {
        let (settings, theme) = loadSettings()
        return TimelineInput(
            account: account,
            snapshot: snapshot,
            status: status,
            meterKeys: (intent.meters ?? []).map(\.key),
            settings: settings,
            theme: theme,
            family: family
        )
    }

    /// Maps a registry `AccountEntry.status` string (the `Diagnostics.statusName` spelling) to a status.
    /// Returns nil for "ok", "active" and unknown values, so freshness falls back to cache age.
    static func persistedStatus(_ raw: String) -> AccountStatus? {
        switch raw {
        case "needsLogin": .needsLogin
        case "codexNotSignedIn": .codexNotSignedIn
        case "schemaError": .schemaError
        case "ghMissing": .ghMissing
        case "ghLoginRemoved": .ghLoginRemoved
        case "claudeCodeNotSignedIn": .claudeCodeNotSignedIn
        case "claudeCodeExpired": .claudeCodeExpired
        case "claudeCodeDenied": .claudeCodeDenied
        case "quotaUnavailable": .quotaUnavailable
        case "offline": .offline
        default: nil
        }
    }

    static func kind(_ family: WidgetFamily) -> WidgetFamilyKind {
        switch family {
        case .accessoryCircular: .circular
        case .accessoryInline: .inline
        case .accessoryRectangular: .rectangular
        default: .small
        }
    }

    static func placeholderEntry(now: Date) -> UsageEntry {
        let id = AccountID(rawValue: "claude:placeholder")!
        let snapshot = UsageSnapshot(accountID: id, fetchedAt: now, meters: [
            Meter(kind: .session5h, label: "5-hour", percentUsed: 40, resetsAt: now.addingTimeInterval(7200), windowLength: .seconds(18000)),
            Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 60, resetsAt: now.addingTimeInterval(3 * 86400), windowLength: .seconds(604_800)),
        ])
        let account = AccountEntry(id: id, kind: .claude, displayName: "Claude", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
        return UsageEntry(date: now, account: account, snapshot: snapshot, status: .fresh, meterKeys: [], settings: .default, theme: .default, relevance: nil)
    }
}

/// Resumes a continuation exactly once; `resume` reports whether this call won.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?
    private var pending: T?
    private var done = false

    func set(_ c: CheckedContinuation<T, Never>) {
        lock.lock(); defer { lock.unlock() }
        if let pending { c.resume(returning: pending) } else { cont = c }
    }

    @discardableResult
    func resume(_ value: T) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return false }
        done = true
        if let cont { cont.resume(returning: value); self.cont = nil } else { pending = value }
        return true
    }
}

/// Holds the timeout timer so a winning fetch can cancel it, whichever is set first.
private final class TimerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false

    func set(_ t: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        if cancelled { t.cancel() } else { task = t }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
