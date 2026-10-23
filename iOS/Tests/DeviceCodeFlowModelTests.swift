import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private let id = AccountID(kind: .codex, remoteID: "u1")

private func prompt(expiresIn: TimeInterval = 600) -> DeviceCodePrompt {
    DeviceCodePrompt(
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        interval: .seconds(5),
        expiresAt: Date().addingTimeInterval(expiresIn),
        deviceCode: Secret("dc"),
    )
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    func set() { lock.withLock { v = true } }
    var value: Bool { lock.withLock { v } }
}

@MainActor private func waitUntil(_ cond: () -> Bool) async {
    for _ in 0..<300 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor struct DeviceCodeFlowModelTests {
    @Test func testHappyPath() async {
        let p = prompt()
        let m = DeviceCodeFlowModel(title: "T", start: { p }, complete: { _ in
            try await Task.sleep(for: .milliseconds(100))
            return id
        })
        m.begin()
        await waitUntil { m.state == .waiting(p) }
        #expect(m.state == .waiting(p))
        await waitUntil { m.state == .success(id) }
        #expect(m.state == .success(id))
    }

    @Test func testExpiry() async {
        let starts = Counter()
        let m = DeviceCodeFlowModel(
            title: "T",
            start: { starts.bump(); return prompt(expiresIn: 60) },
            complete: { _ in try await Task.sleep(for: .seconds(30)); return id },
            now: { Date().addingTimeInterval(120) },
        )
        m.begin()
        await waitUntil { m.state == .expired }
        #expect(m.state == .expired)
        m.restart()
        await waitUntil { starts.value == 2 }
        #expect(starts.value == 2)
        m.cancel()
    }

    @Test func testDismissCancelsPolling() async {
        let entered = Flag()
        let cancelled = Flag()
        let m = DeviceCodeFlowModel(title: "T", start: { prompt() }, complete: { _ in
            entered.set()
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.set(); throw error }
            return id
        })
        m.begin()
        await waitUntil { entered.value }
        m.cancel()
        await waitUntil { cancelled.value }
        #expect(cancelled.value)
        #expect(m.state != .success(id))
    }

    @Test func testStartFailure() async {
        struct E: Error {}
        let m = DeviceCodeFlowModel(title: "T", start: { throw E() }, complete: { _ in id })
        m.begin()
        await waitUntil { m.state != .starting }
        #expect(m.state == .failed("Couldn't get a code"))
    }

    @Test func testCompleteFailure() async {
        struct E: Error {}
        let m = DeviceCodeFlowModel(title: "T", start: { prompt() }, complete: { _ in throw E() })
        m.begin()
        await waitUntil { if case .failed = m.state { true } else { false } }
        #expect(m.state == .failed("Sign-in failed"))
    }

    @Test func testForegroundWakesPollOnlyWhileWaiting() async {
        let wakes = Counter()
        let p = prompt()
        let m = DeviceCodeFlowModel(
            title: "T",
            start: { p },
            complete: { _ in try await Task.sleep(for: .seconds(30)); return id },
            wake: { wakes.bump() },
        )
        m.foreground()
        #expect(wakes.value == 0, "nothing to wake before begin")
        m.begin()
        await waitUntil { m.state == .waiting(p) }
        m.foreground()
        #expect(wakes.value == 1)
        m.cancel()
    }
}
