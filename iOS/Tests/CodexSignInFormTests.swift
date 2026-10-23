import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct CodexSignInFormTests {
    private let p = DeviceCodePrompt(
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        interval: .seconds(5),
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        deviceCode: Secret("dc"),
    )
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var waiting: DeviceCodeFlowModel.State { .waiting(p) }

    @Test func testStartingAndWaitingStepOneCurrent() {
        let f = CodexSignInForm()
        #expect(f.steps(.starting) == [.current, .todo, .todo])
        #expect(f.steps(waiting) == [.current, .todo, .todo])
        #expect(f.copyProminent(waiting))
        #expect(!f.openProminent(waiting))
        #expect(f.waitLine(waiting, now: t0) == nil)
    }

    @Test func testCopyAdvancesToStepTwo() {
        var f = CodexSignInForm()
        f.copy()
        #expect(f.steps(waiting) == [.done, .current, .todo])
        #expect(!f.copyProminent(waiting))
        #expect(f.openProminent(waiting))
    }

    @Test func testOpenWithoutCopyMarksStepOneDone() {
        var f = CodexSignInForm()
        f.open()
        #expect(f.steps(waiting) == [.done, .current, .todo])
        #expect(!f.openProminent(waiting), "Open goes quiet once the browser was shown")
    }

    @Test func testReturnAfterOpenShowsFinishing() {
        var f = CodexSignInForm()
        f.copy()
        f.open()
        f.cameBack(at: t0, state: waiting)
        #expect(f.steps(waiting) == [.done, .done, .current])
        #expect(f.waitLine(waiting, now: t0) == .finishing)
        #expect(f.waitLine(waiting, now: t0.addingTimeInterval(29.9)) == .finishing)
    }

    @Test func testStillWaitingAfterThirtySeconds() {
        var f = CodexSignInForm()
        f.open()
        f.cameBack(at: t0, state: waiting)
        #expect(f.stillWaitingAt == t0.addingTimeInterval(30))
        #expect(f.waitLine(waiting, now: t0.addingTimeInterval(30)) == .stillWaiting)
        #expect(f.waitLine(waiting, now: t0.addingTimeInterval(300)) == .stillWaiting)
    }

    @Test func testReopenAndReturnRestartsTheThirtySeconds() {
        var f = CodexSignInForm()
        f.open()
        f.cameBack(at: t0, state: waiting)
        let later = t0.addingTimeInterval(40)
        // A second active phase without leaving for the browser (Control Center) keeps the clock.
        f.cameBack(at: later, state: waiting)
        #expect(f.waitLine(waiting, now: later) == .stillWaiting)
        f.open()
        f.cameBack(at: later, state: waiting)
        #expect(f.waitLine(waiting, now: later) == .finishing)
        #expect(f.waitLine(waiting, now: later.addingTimeInterval(30)) == .stillWaiting)
    }

    @Test func testReturnWithoutOpenDoesNothing() {
        var f = CodexSignInForm()
        f.copy()
        f.cameBack(at: t0, state: waiting)
        #expect(f.steps(waiting) == [.done, .current, .todo])
        #expect(f.waitLine(waiting, now: t0.addingTimeInterval(60)) == nil)
    }

    @Test func testReturnOutsideWaitingDoesNothing() {
        var f = CodexSignInForm()
        f.open()
        f.cameBack(at: t0, state: .expired)
        #expect(f.returnedAt == nil)
    }

    @Test func testFinishedStatesShowAllDoneAndNoWaitLine() {
        var f = CodexSignInForm()
        f.open()
        f.cameBack(at: t0, state: waiting)
        let id = AccountID(kind: .codex, remoteID: "r")
        for s in [DeviceCodeFlowModel.State.expired, .failed("x"), .success(id)] {
            #expect(f.steps(s) == [.done, .done, .done])
            #expect(f.waitLine(s, now: t0.addingTimeInterval(60)) == nil)
            #expect(!f.copyProminent(s))
            #expect(!f.openProminent(s))
        }
    }

    @Test func testCopyNotProminentWhileStarting() {
        #expect(!CodexSignInForm().copyProminent(.starting))
    }

    @Test func testResetClearsEverything() {
        var f = CodexSignInForm()
        f.copy()
        f.open()
        f.cameBack(at: t0, state: waiting)
        f.reset()
        #expect(f == CodexSignInForm())
        #expect(f.steps(.starting) == [.current, .todo, .todo])
    }
}
