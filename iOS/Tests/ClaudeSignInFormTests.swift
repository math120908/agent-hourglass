import Testing
import UsageCore
@testable import AgentHourglass

struct ClaudeSignInFormTests {
    private let valid = "abc#state-123"
    private let id = AccountID(kind: .claude, remoteID: "r")

    @Test func testInitialStepOneCurrent() {
        let f = ClaudeSignInForm()
        #expect(f.steps(.browsing) == [.current, .todo, .todo])
        #expect(!f.canContinue(.browsing))
        #expect(!f.pasteProminent(.browsing))
    }

    @Test func testReturnAdvancesToStepTwo() {
        var f = ClaudeSignInForm()
        f.returned(hasStrings: false)
        #expect(f.steps(.browsing) == [.done, .current, .todo])
    }

    @Test func testPasteProminenceFollowsHasStrings() {
        var f = ClaudeSignInForm()
        f.returned(hasStrings: true)
        #expect(f.pasteProminent(.browsing))
        f.returned(hasStrings: false)
        #expect(!f.pasteProminent(.browsing))
        f.returned(hasStrings: true)
        f.pasted(valid)
        #expect(!f.pasteProminent(.browsing), "a landed code drops back to the icon button")
        #expect(!f.pasteProminent(.exchanging))
    }

    @Test func testNotOpenedNeverProminent() {
        var f = ClaudeSignInForm()
        f.hasStrings = true
        #expect(!f.pasteProminent(.browsing))
    }

    @Test func testParsableGatesContinue() {
        var f = ClaudeSignInForm()
        f.returned(hasStrings: true)
        f.text = "abc"
        #expect(!f.canContinue(.browsing))
        #expect(f.steps(.browsing) == [.done, .current, .current])
        f.text = valid
        #expect(f.canContinue(.browsing))
        #expect(f.steps(.browsing) == [.done, .done, .done])
        #expect(!f.canContinue(.exchanging))
        // State is required: a bare code or an empty state never enables Continue.
        f.text = "abc#"
        #expect(!f.canContinue(.browsing))
    }

    @Test func testInvalidCaptionImmediateOnPasteOnly() {
        var f = ClaudeSignInForm()
        f.text = "ab"
        #expect(f.isInvalid)
        #expect(!f.showsInvalid, "typing waits for the debounce")
        f.pasted("abc")
        #expect(f.showsInvalid)
        f.pasted(valid)
        #expect(!f.showsInvalid)
    }

    @Test func testTypingDebouncesCaption() {
        var f = ClaudeSignInForm()
        f.text = "ab"
        do { let scheduled = f.edited(); #expect(scheduled, "invalid and not shown: schedule the debounce") }
        #expect(!f.showsInvalid)
        f.debounceElapsed()
        #expect(f.showsInvalid)
        f.text = "abc"
        do { let scheduled = f.edited(); #expect(!scheduled, "already shown: no second debounce") }
        #expect(f.showsInvalid)
        f.text = valid
        do { let scheduled = f.edited(); #expect(!scheduled) }
        #expect(!f.showsInvalid)
        f.text = ""
        do { let scheduled = f.edited(); #expect(!scheduled) }
        #expect(!f.showsInvalid)
    }

    @Test func testPasteThenEditKeepsImmediateCaption() {
        var f = ClaudeSignInForm()
        f.pasted("abc")
        // The text change from the paste reaches `edited()` too; it must not hide the caption.
        do { let scheduled = f.edited(); #expect(!scheduled) }
        #expect(f.showsInvalid)
    }

    @Test func testFinishedStatesShowAllDone() {
        let f = ClaudeSignInForm()
        for s in [ClaudeSignInModel.State.exchanging, .success(id), .failed("x")] {
            #expect(f.steps(s) == [.done, .done, .done])
        }
    }

    @Test func testTryAgainClearsTextAndResetsStep() {
        var f = ClaudeSignInForm()
        f.returned(hasStrings: true)
        f.pasted(valid)
        f.reset()
        #expect(f.text.isEmpty)
        #expect(!f.showsInvalid)
        #expect(f.steps(.browsing) == [.current, .todo, .todo])
        #expect(!f.pasteProminent(.browsing))
    }
}
