import Foundation
import Testing
@testable import UsageCore

/// Holds every request until `released`, ignoring cancellation like an in-flight URLSession POST.
final class GatedTransport: HTTPTransport, @unchecked Sendable {
    let inner: ScriptedTransport
    let entered = CodexTestBox(false)
    let released = CodexTestBox(false)
    init(_ inner: ScriptedTransport) { self.inner = inner }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        entered.value = true
        while !released.value { try? await Task.sleep(for: .milliseconds(5)) }
        return try await inner.data(for: request)
    }
}

/// Foreground return: `wake` cuts the wait short only once the current interval has elapsed.
struct CodexDevicePollWakeTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let m0 = ContinuousClock.now
    let clock = CodexTestBox(t0)
    let mono = CodexTestBox(m0)
    let sleeps = CodexTestBox<[Duration]>([])

    /// Moves wall and monotonic clocks together, `secs` after the start.
    func advance(_ secs: Double) {
        clock.value = Self.t0.addingTimeInterval(secs)
        mono.value = Self.m0 + .seconds(secs)
    }

    /// A sleep that never ends on its own: only a wake (or cancellation) moves the loop on.
    func auth(_ t: ScriptedTransport) -> CodexDeviceAuth {
        let clock = clock, mono = mono, sleeps = sleeps
        return CodexDeviceAuth(
            http: HTTPClient(transport: t),
            sleep: { d in sleeps.value.append(d); try await Task.sleep(for: .seconds(600)) },
            now: { clock.value },
            monotonic: { mono.value }
        )
    }

    func prompt() -> DeviceCodePrompt {
        DeviceCodePrompt(
            userCode: "ABCD-1234",
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            interval: .seconds(5),
            expiresAt: Self.t0.addingTimeInterval(900),
            deviceCode: Secret("DAID-SENTINEL")
        )
    }

    private func waitUntil(_ cond: () -> Bool) async {
        for _ in 0..<300 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func pollCount(_ t: ScriptedTransport) -> Int {
        t.requests.filter { $0.url?.path() == "/api/accounts/deviceauth/token" }.count
    }

    @Test func wakeAfterIntervalPollsAtOnce() async throws {
        let t = ScriptedTransport([CodexDeviceAuthTests.pending, CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        advance(6)
        wake.fire()
        let c = try await task.value
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(pollCount(t) == 2)
        #expect(sleeps.value == [.seconds(5)])
    }

    @Test func wakeBeforeIntervalWaitsOutTheRest() async throws {
        let t = ScriptedTransport([CodexDeviceAuthTests.pending, CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        advance(2)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(5), .seconds(3)])
        #expect(pollCount(t) == 1, "never sooner than the interval")
        advance(5)
        wake.fire()
        _ = try await task.value
        #expect(pollCount(t) == 2)
    }

    @Test func wakeHonoursSlowDown() async throws {
        let t = ScriptedTransport([(429, "", [:]), CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        #expect(sleeps.value == [.seconds(10)])
        advance(6)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(10), .seconds(4)])
        #expect(pollCount(t) == 1)
        advance(10)
        wake.fire()
        _ = try await task.value
        #expect(pollCount(t) == 2)
    }

    @Test func wallClockJumpDoesNotPollEarly() async throws {
        // The user sets the clock forward while in Safari: only real elapsed time counts.
        let t = ScriptedTransport([CodexDeviceAuthTests.pending, CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        clock.value = Self.t0.addingTimeInterval(60)
        mono.value = Self.m0 + .seconds(2)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(5), .seconds(3)])
        #expect(pollCount(t) == 1, "a wall-clock jump is not elapsed time")
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func slowDownPersistsAcrossLaterWakes() async throws {
        // 429 bumps the interval to 10 s; it holds for the next poll and its wake too.
        let t = ScriptedTransport([(429, "", [:]), CodexDeviceAuthTests.pending, CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        advance(10)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(pollCount(t) == 2)
        #expect(sleeps.value == [.seconds(10), .seconds(10)], "not reset to 5 s")
        advance(16)
        wake.fire()
        await waitUntil { sleeps.value.count == 3 }
        #expect(sleeps.value == [.seconds(10), .seconds(10), .seconds(4)])
        #expect(pollCount(t) == 2, "6 s after the second poll is still inside 10 s")
        advance(20)
        wake.fire()
        _ = try await task.value
        #expect(pollCount(t) == 3)
    }

    @Test func wakeDuringRequestDoesNotSkipTheInterval() async throws {
        // A fire with nobody waiting is kept, but the elapsed check still holds the interval.
        let t = ScriptedTransport([CodexDeviceAuthTests.pending, CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let wake = DevicePollWake()
        wake.fire()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(5), .seconds(5)])
        #expect(pollCount(t) == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelDuringTokenRequestSkipsTheExchange() async throws {
        // A restart cancels the old login while its token POST is in flight; the code it returns is dropped.
        let inner = ScriptedTransport([CodexDeviceAuthTests.code, CodexDeviceAuthTests.tokens()])
        let t = GatedTransport(inner)
        let a = CodexDeviceAuth(http: HTTPClient(transport: t), sleep: { _ in }, now: { Self.t0 }, monotonic: { Self.m0 })
        let gated = Task { try await a.poll(prompt()) }
        await waitUntil { t.entered.value }
        gated.cancel()
        t.released.value = true
        await #expect(throws: CancellationError.self) { try await gated.value }
        #expect(!inner.requests.contains { $0.url?.path() == "/oauth/token" }, "no exchange for a cancelled login")
    }

    @Test func cancellationWhileWaitingStops() async throws {
        let t = ScriptedTransport([CodexDeviceAuthTests.pending])
        let wake = DevicePollWake()
        let a = auth(t)
        let task = Task { try await a.poll(prompt(), wake: wake) }
        await waitUntil { sleeps.value.count == 1 }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(pollCount(t) == 1)
    }
}
