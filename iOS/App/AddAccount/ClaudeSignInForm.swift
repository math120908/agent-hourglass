import UsageCore

/// View-side state of the Claude paste sign-in: what the user has done on this screen. The
/// server outcome lives in `ClaudeSignInModel.State`; the pasteboard is never read here.
struct ClaudeSignInForm: Equatable {
    typealias Step = SignInStep

    var text = ""
    /// The sign-in page was shown at least once (the auth session completion handler fired).
    var opened = false
    /// `UIPasteboard.hasStrings` at the last return: a string exists, its content is unknown.
    var hasStrings = false
    /// Gate for the inline "isn't complete" caption: debounced while typing, immediate on paste.
    var showsInvalid = false

    var parsable: Bool { ClaudeManualCallback.parse(pasted: text) != nil }
    var isInvalid: Bool { !text.isEmpty && !parsable }

    /// Rows 1-3. Every non-browsing state shows the finished checklist above its result.
    func steps(_ state: ClaudeSignInModel.State) -> [Step] {
        guard state == .browsing, !parsable else { return [.done, .done, .done] }
        return [opened ? .done : .current, opened ? .current : .todo, text.isEmpty ? .todo : .current]
    }

    func canContinue(_ state: ClaudeSignInModel.State) -> Bool { state == .browsing && parsable }

    /// The PasteButton grows into `[icon Paste]` only once the user came back with a string to paste.
    func pasteProminent(_ state: ClaudeSignInModel.State) -> Bool {
        state == .browsing && opened && hasStrings && text.isEmpty
    }

    mutating func returned(hasStrings: Bool) {
        opened = true
        self.hasStrings = hasStrings
    }

    /// The user did not type, so a bad paste is flagged at once.
    mutating func pasted(_ s: String) {
        text = s
        showsInvalid = isInvalid
    }

    /// After a keystroke: hides the caption once the text is fine. Returns true when the caption
    /// should appear after the debounce (still invalid and not shown yet).
    mutating func edited() -> Bool {
        guard isInvalid else {
            showsInvalid = false
            return false
        }
        return !showsInvalid
    }

    mutating func debounceElapsed() { showsInvalid = isInvalid }

    mutating func reset() { self = Self() }
}
