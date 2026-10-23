import Testing
@testable import AgentHourglass

struct AccountsSectionTests {
    @Test func testBlankRenameReverts() {
        #expect(AccountsSection.committedName("  ", current: "Snorlax") == nil)
        #expect(AccountsSection.committedName("", current: "Snorlax") == nil)
    }

    @Test func testUnchangedRenameSkipped() {
        #expect(AccountsSection.committedName("Snorlax", current: "Snorlax") == nil)
        #expect(AccountsSection.committedName(" Snorlax ", current: "Snorlax") == nil)
    }

    @Test func testTrimmedRename() {
        #expect(AccountsSection.committedName(" Snorlax 2 ", current: "Snorlax") == "Snorlax 2")
    }
}
