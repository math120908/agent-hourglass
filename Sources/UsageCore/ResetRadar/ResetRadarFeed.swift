import Foundation

public struct ResetRadarSettings: Sendable, Equatable {
    public var show = true
    public var notify = true
    public var notifyCredits = false

    public init(show: Bool = true, notify: Bool = true, notifyCredits: Bool = false) {
        self.show = show
        self.notify = notify
        self.notifyCredits = notifyCredits
    }
}

/// Persists the dedupe keys already seen. `nil` means first run.
public protocol ResetRadarStorage: Sendable {
    func seenKeys() -> Set<String>?
    func setSeenKeys(_ keys: Set<String>)
}

public final class UserDefaultsResetRadarStorage: ResetRadarStorage, @unchecked Sendable {
    public static let key = "resetRadar.seenKeys"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func seenKeys() -> Set<String>? {
        (defaults.array(forKey: Self.key) as? [String]).map(Set.init)
    }

    public func setSeenKeys(_ keys: Set<String>) {
        defaults.set(keys.sorted(), forKey: Self.key)
    }
}

/// Polls the codex-reset.com timeline and decides which events to notify.
public actor ResetRadarFeed {
    public static let url = URL(string: "https://codex-reset.com/api/timeline")!
    public static let interval: Duration = .seconds(3600)
    static let minimumGap: TimeInterval = 60

    public private(set) var events: [ResetEvent] = []

    private let http: HTTPClient
    private let storage: ResetRadarStorage
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var lastAttempt: Date?
    private var blockedUntil: Date?

    public init(http: HTTPClient, storage: ResetRadarStorage, userAgent: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.http = http
        self.storage = storage
        self.userAgent = userAgent
        self.now = now
    }

    /// Fetches once (no-op returning [] if the last attempt was < 60 s ago or a 429 back-off is
    /// active), updates `events`, and returns the events to notify. Never throws: on failure the
    /// previous `events` are kept and nothing is notified.
    public func check(settings: ResetRadarSettings) async -> [ResetEvent] {
        let start = now()
        if let lastAttempt, start.timeIntervalSince(lastAttempt) < Self.minimumGap { return [] }
        if let blockedUntil, start < blockedUntil { return [] }
        lastAttempt = start

        var request = URLRequest(url: Self.url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let all: [ResetEvent]
        do {
            let (data, _) = try await http.send(request, bearer: nil)
            all = try ResetRadarLogic.decode(data)
        } catch ProviderError.rateLimited(let retryAfter) {
            blockedUntil = retryAfter.map { start.addingTimeInterval(TimeInterval($0.components.seconds)) }
            return []
        } catch {
            return []
        }

        events = ResetRadarLogic.merged(all)
        let result = ResetRadarLogic.pending(all, seen: storage.seenKeys(), includeCredits: settings.notifyCredits)
        storage.setSeenKeys(result.seen)
        return settings.notify ? result.notify : []
    }
}
