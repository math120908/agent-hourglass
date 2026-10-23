import Foundation
import Testing
@testable import AgentHourglass

private final class FakeSession: PasteAuthSession {
    var started = 0
    var cancelled = 0
    let done: @Sendable () -> Void
    init(done: @escaping @Sendable () -> Void) { self.done = done }
    func start() -> Bool { started += 1; return true }
    func cancel() { cancelled += 1 }
}

@MainActor
struct PasteBrowserTests {
    private let url = URL(string: "https://claude.ai/oauth/authorize")!

    private func browser() -> (PasteBrowser, () -> [FakeSession]) {
        var made: [FakeSession] = []
        let b = PasteBrowser { _, _, done in
            let s = FakeSession(done: done)
            made.append(s)
            return s
        }
        return (b, { made })
    }

    private func drain() async { for _ in 0..<20 { await Task.yield() } }

    @Test func returnFiresOnceWhenSessionEnds() async {
        let (b, made) = browser()
        var returns = 0
        b.open(url) { returns += 1 }
        #expect(made().count == 1 && made()[0].started == 1)
        #expect(b.isActive)
        made()[0].done()
        await drain()
        #expect(returns == 1)
        #expect(!b.isActive)
    }

    @Test func cancelReleasesSessionAndSuppressesReturn() async {
        let (b, made) = browser()
        var returns = 0
        b.open(url) { returns += 1 }
        b.cancel()
        #expect(made()[0].cancelled == 1)
        #expect(!b.isActive)
        made()[0].done()
        await drain()
        #expect(returns == 0)
    }

    @Test func reopenIgnoresPreviousSession() async {
        let (b, made) = browser()
        var returns = 0
        b.open(url) { returns += 1 }
        b.open(url) { returns += 10 }
        #expect(made()[0].cancelled == 1)
        made()[0].done()
        await drain()
        #expect(returns == 0)
        #expect(b.isActive)
        made()[1].done()
        await drain()
        #expect(returns == 10)
    }

    @Test func cancelWithoutOpenIsHarmless() {
        let (b, _) = browser()
        b.cancel()
        #expect(!b.isActive)
    }
}
