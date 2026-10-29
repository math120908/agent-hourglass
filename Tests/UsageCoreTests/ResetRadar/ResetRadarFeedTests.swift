import Foundation
import Testing
@testable import UsageCore

final class MemoryResetRadarStorage: ResetRadarStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<String>?
    init(_ keys: Set<String>? = nil) { self.keys = keys }
    func seenKeys() -> Set<String>? { lock.withLock { keys } }
    func setSeenKeys(_ keys: Set<String>) { lock.withLock { self.keys = keys } }
}

final class RadarClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

struct ResetRadarFeedTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let ua = "AgentHourglass/1.2.3 (+https://github.com/math120908/agent-hourglass)"

    static func timeline() throws -> String { String(decoding: try fixture("codex-reset-timeline"), as: UTF8.self) }

    static func feed(_ t: ScriptedTransport, _ storage: ResetRadarStorage, _ clock: RadarClock) -> ResetRadarFeed {
        ResetRadarFeed(http: HTTPClient(transport: t), storage: storage, userAgent: ua, now: { clock.now })
    }

    @Test func sendsUserAgentNoBearer() async throws {
        let t = ScriptedTransport([(200, try Self.timeline(), [:])])
        let feed = Self.feed(t, MemoryResetRadarStorage(), RadarClock(Self.start))
        _ = await feed.check(settings: ResetRadarSettings())
        #expect(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.url == ResetRadarFeed.url)
        #expect(r.url?.host == "codex-reset.com")
        #expect(r.value(forHTTPHeaderField: "User-Agent") == Self.ua)
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(await feed.events.count == 5)
    }

    @Test func fetchFailureKeepsPrevious() async throws {
        let t = ScriptedTransport([(200, try Self.timeline(), [:]), (503, "", [:])])
        let clock = RadarClock(Self.start)
        let feed = Self.feed(t, MemoryResetRadarStorage(), clock)
        _ = await feed.check(settings: ResetRadarSettings())
        let before = await feed.events
        clock.advance(3600)
        let notify = await feed.check(settings: ResetRadarSettings())
        #expect(t.requests.count == 2)
        #expect(notify.isEmpty)
        #expect(await feed.events == before)
        #expect(!before.isEmpty)
    }

    @Test func throttlesWithin60s() async throws {
        let t = ScriptedTransport([(200, try Self.timeline(), [:])])
        let feed = Self.feed(t, MemoryResetRadarStorage(), RadarClock(Self.start))
        _ = await feed.check(settings: ResetRadarSettings())
        let second = await feed.check(settings: ResetRadarSettings())
        #expect(second.isEmpty)
        #expect(t.requests.count == 1)
    }

    @Test func notifiesNewConfirmedReset() async throws {
        let storage = MemoryResetRadarStorage(["reset|2026-10-26"])
        let t = ScriptedTransport([(200, try Self.timeline(), [:])])
        let notify = await Self.feed(t, storage, RadarClock(Self.start)).check(settings: ResetRadarSettings())
        #expect(notify.map(\.dedupeKey).contains("reset|2026-10-28"))
        #expect(!notify.contains { $0.kind == .credits })
        #expect(storage.seenKeys()?.contains("reset|2026-10-28") == true)
    }

    @Test func notifyOffStillAdvancesSeen() async throws {
        let storage = MemoryResetRadarStorage([])
        let t = ScriptedTransport([(200, try Self.timeline(), [:]), (200, try Self.timeline(), [:])])
        let clock = RadarClock(Self.start)
        let feed = Self.feed(t, storage, clock)
        var off = ResetRadarSettings()
        off.notify = false
        #expect(await feed.check(settings: off).isEmpty)
        #expect(storage.seenKeys()?.contains("reset|2026-10-28") == true)
        clock.advance(3600)
        #expect(await feed.check(settings: ResetRadarSettings()).isEmpty)
    }

    @Test func firstRunSeedsStorage() async throws {
        let storage = MemoryResetRadarStorage()
        let t = ScriptedTransport([(200, try Self.timeline(), [:])])
        let notify = await Self.feed(t, storage, RadarClock(Self.start)).check(settings: ResetRadarSettings())
        #expect(notify.isEmpty)
        #expect(storage.seenKeys()?.isEmpty == false)
    }

    @Test func rateLimitedHonoursRetryAfter() async throws {
        let t = ScriptedTransport([(429, "", ["Retry-After": "120"]), (200, try Self.timeline(), [:])])
        let clock = RadarClock(Self.start)
        let feed = Self.feed(t, MemoryResetRadarStorage(), clock)
        _ = await feed.check(settings: ResetRadarSettings())
        clock.advance(61)
        _ = await feed.check(settings: ResetRadarSettings())
        #expect(t.requests.count == 1)
        clock.advance(60)
        _ = await feed.check(settings: ResetRadarSettings())
        #expect(t.requests.count == 2)
        #expect(await feed.events.count == 5)
    }

    @Test func userDefaultsStorageRoundTrip() throws {
        let suite = "reset-radar-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsResetRadarStorage(defaults: defaults)
        #expect(storage.seenKeys() == nil)
        storage.setSeenKeys(["reset|2026-10-28", "credits|2026-10-07"])
        #expect(UserDefaultsResetRadarStorage(defaults: defaults).seenKeys() == ["reset|2026-10-28", "credits|2026-10-07"])
        #expect(defaults.object(forKey: "resetRadar.seenKeys") != nil)
    }
}
