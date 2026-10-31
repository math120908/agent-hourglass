import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

// Synthetic Firebase auth-user values; no live payload.
private enum ELBodies {
    static let session = #"[{"uid":"uid-synthetic","email":"x@y","stsTokenManager":{"refreshToken":"REFRESH-SENTINEL"}}]"#
    static let empty = "[]"
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@MainActor struct ElevenLabsSignInModelTests {
    private let expected = AccountID(kind: .elevenlabs, remoteID: "uid-synthetic")

    private func settle(_ m: ElevenLabsSignInModel) async throws {
        for _ in 0..<300 where m.phase == .finishing { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func testNilAndEmptyAreIgnored() {
        let m = ElevenLabsSignInModel(refresh: { $0 }, add: { _ in Issue.record("add called"); throw CancellationError() })
        m.receive(probeResult: nil)
        m.receive(probeResult: ELBodies.empty)
        m.receive(probeResult: "not json")
        #expect(m.phase == .browsing)
    }

    @Test func testValidSessionRefreshesAndAdds() async throws {
        let m = ElevenLabsSignInModel(
            refresh: { seed in
                #expect(seed.refresh?.reveal() == "REFRESH-SENTINEL")
                return seed
            },
            add: { cred in AccountID(kind: .elevenlabs, remoteID: cred.remoteAccountID ?? "") },
        )
        m.receive(probeResult: ELBodies.session)
        #expect(m.phase == .finishing)
        try await settle(m)
        #expect(m.phase == .done(expected))
    }

    @Test func testRefreshErrorFails() async throws {
        let m = ElevenLabsSignInModel(refresh: { _ in throw ProviderError.invalidGrant }, add: { _ in throw CancellationError() })
        m.receive(probeResult: ELBodies.session)
        try await settle(m)
        #expect(m.phase == .failed("The new sign-in was rejected. Retry"))
    }

    @Test func testSecondProbeWhileFinishingIsIgnored() async throws {
        let adds = Counter()
        let m = ElevenLabsSignInModel(
            refresh: { seed in
                try await Task.sleep(for: .milliseconds(50))
                return seed
            },
            add: { _ in
                adds.bump()
                return AccountID(kind: .elevenlabs, remoteID: "uid-synthetic")
            },
        )
        m.receive(probeResult: ELBodies.session)
        m.receive(probeResult: ELBodies.session)
        try await settle(m)
        m.receive(probeResult: ELBodies.session)
        try await Task.sleep(for: .milliseconds(100))
        #expect(m.phase == .done(expected))
        #expect(adds.value == 1)
    }
}
