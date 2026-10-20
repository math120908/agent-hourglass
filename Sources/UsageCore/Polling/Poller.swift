import Foundation

/// Drives every AccountClient on one schedule. Provider-agnostic: it only sees AccountClient.
/// Time comes from `now`; the loop sleeps on `clock`. Tests call `tick()` directly.
public actor Poller {
    public static let wakeSettle: TimeInterval = 10
    public static let staleOnOpen: TimeInterval = 60

    public typealias OnResult = @Sendable (AccountID, FetchOutcome) async -> Void

    private var clients: [AccountID: AccountClient] = [:]
    private var order: [AccountID] = []
    private var nextDue: [AccountID: Date] = [:]
    private var lastAttempt: [AccountID: Date] = [:]
    private var lastSuccess: [AccountID: Date] = [:]

    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> Double
    private let floor: Duration
    private let onResult: OnResult
    private let recorder: (any HistoryRecording)?

    public private(set) var schedule = PollSchedule()
    private var asleep = false
    private var offline = false
    private var wakeAt: Date?
    private var loop: Task<Void, Never>?

    /// `jitter` returns a factor in [-0.05, 0.05] applied to each interval. `floor` is the per-provider minimum.
    public init(
        clients: [AccountClient],
        clock: any Clock<Duration>,
        now: @escaping @Sendable () -> Date,
        floor: Duration = .seconds(60),
        jitter: @escaping @Sendable () -> Double = { Double.random(in: -0.05...0.05) },
        recorder: (any HistoryRecording)? = nil,
        onResult: @escaping OnResult
    ) {
        self.clock = clock
        self.now = now
        self.floor = floor
        self.jitter = jitter
        self.onResult = onResult
        self.recorder = recorder
        let t = now()
        let interval = schedule.effectiveInterval(floor: floor)
        for c in clients {
            self.clients[c.id] = c
            order.append(c.id)
            nextDue[c.id] = t.addingTimeInterval(Backoff.seconds(staggerOffset(for: c.id, interval: interval)))
        }
    }

    public var interval: Duration { schedule.effectiveInterval(floor: floor) }

    public func add(client: AccountClient) {
        guard clients[client.id] == nil else { return }
        clients[client.id] = client
        order.append(client.id)
        nextDue[client.id] = now()
    }

    public func remove(client id: AccountID) {
        clients[id] = nil
        order.removeAll { $0 == id }
        nextDue[id] = nil
        lastAttempt[id] = nil
        lastSuccess[id] = nil
    }

    /// Popover open/close. Opening fetches at once for accounts with no success in the last 60 s.
    public func setForeground(_ fg: Bool) async {
        guard schedule.isForeground != fg else { return }
        schedule.isForeground = fg
        reschedule()
        guard fg, canPoll else { return }
        let t = now()
        for id in order where (lastSuccess[id].map { t.timeIntervalSince($0) >= Self.staleOnOpen } ?? true) {
            await fetch(id, at: t)
        }
    }

    public func setUserInterval(_ d: Duration) {
        schedule.userInterval = d
        reschedule()
    }

    /// Manual refresh. Never closer than `floor` to the previous attempt, even with `force`.
    /// `force` ignores the regular schedule; the floor and client backoff still apply.
    public func refreshAll(force: Bool) async {
        guard canPoll else { return }
        let t = now()
        let floorS = Backoff.seconds(floor)
        for id in order {
            if let last = lastAttempt[id], t.timeIntervalSince(last) < floorS { continue }
            if !force, let due = nextDue[id], t < due { continue }
            await fetch(id, at: t)
        }
    }

    public func sleep() { asleep = true; wakeAt = nil }

    public func wake() {
        asleep = false
        wakeAt = now().addingTimeInterval(Self.wakeSettle)
    }

    public func setOffline(_ off: Bool) { offline = off }

    /// One scheduler step: fetch every due account.
    public func tick() async {
        guard canPoll else { return }
        let t = now()
        if let w = wakeAt {
            guard t >= w else { return }
            wakeAt = nil
            for id in order { await fetch(id, at: t) }
            return
        }
        for id in order {
            guard let due = nextDue[id], t >= due else { continue }
            await fetch(id, at: t)
        }
    }

    public func start(tickEvery: Duration = .seconds(1)) {
        guard loop == nil else { return }
        let clock = clock
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await clock.sleep(for: tickEvery)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - private

    private var canPoll: Bool { !asleep && !offline }

    private func fetch(_ id: AccountID, at t: Date) async {
        guard let client = clients[id] else { return }
        if await client.status == .needsLogin { nextDue[id] = .distantFuture; return }
        let earliest = await client.nextEarliestFetch
        guard t >= earliest else { nextDue[id] = earliest; return }
        lastAttempt[id] = t
        let outcome = await client.fetch()
        if case .success = outcome { lastSuccess[id] = t }
        var due = t.addingTimeInterval(Backoff.seconds(interval) * (1 + jitter()))
        let after = await client.nextEarliestFetch
        if after > due { due = after }
        if case .failure(.needsLogin) = outcome { due = .distantFuture }
        nextDue[id] = due
        // History is best-effort: a write failure never affects polling.
        if case .success(let snap) = outcome, let recorder { try? await recorder.record(snap) }
        await onResult(id, outcome)
    }

    private func reschedule() {
        let s = Backoff.seconds(interval)
        let t = now()
        for id in order {
            guard nextDue[id] != .distantFuture else { continue }
            let base = lastAttempt[id] ?? t
            nextDue[id] = base.addingTimeInterval(s * (1 + jitter()))
        }
    }
}
