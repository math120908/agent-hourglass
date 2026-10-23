import Foundation
import Testing
@testable import UsageCore

/// Foreground return: `wake` cuts the wait short only once the current interval has elapsed.
struct CodexDevicePollWakeTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = CodexTestBox(t0)
    let sleeps = CodexTestBox<[Duration]>([])

    /// A sleep that never ends on its own: only a wake (or cancellation) moves the loop on.
    func auth(_ t: ScriptedTransport) -> CodexDeviceAuth {
        let clock = clock, sleeps = sleeps
        return CodexDeviceAuth(
            http: HTTPClient(transport: t),
            sleep: { d in sleeps.value.append(d); try await Task.sleep(for: .seconds(600)) },
            now: { clock.value }
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
        clock.value = Self.t0.addingTimeInterval(6)
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
        clock.value = Self.t0.addingTimeInterval(2)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(5), .seconds(3)])
        #expect(pollCount(t) == 1, "never sooner than the interval")
        clock.value = Self.t0.addingTimeInterval(5)
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
        clock.value = Self.t0.addingTimeInterval(6)
        wake.fire()
        await waitUntil { sleeps.value.count == 2 }
        #expect(sleeps.value == [.seconds(10), .seconds(4)])
        #expect(pollCount(t) == 1)
        clock.value = Self.t0.addingTimeInterval(10)
        wake.fire()
        _ = try await task.value
        #expect(pollCount(t) == 2)
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
