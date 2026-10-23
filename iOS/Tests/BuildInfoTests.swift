import Testing
@testable import AgentHourglass

@Test func displayVersionJoinsShortVersionAndBuild() {
    let info: [String: Any] = ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "261024.12345"]
    #expect(BuildInfo.displayVersion(info: info) == "1.0.0 (261024.12345)")
}

@Test func displayVersionFallsBackForMissingOrUnexpandedValues() {
    #expect(BuildInfo.displayVersion(info: [:]) == "dev (dev)")
    let unexpanded: [String: Any] = ["CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": ""]
    #expect(BuildInfo.displayVersion(info: unexpanded) == "dev (dev)")
}

@Test func commitReadsGitCommitKey() {
    #expect(BuildInfo.commit(info: ["GitCommit": "e91d5b3"]) == "e91d5b3")
    #expect(BuildInfo.commit(info: ["GitCommit": "$(GIT_COMMIT)"]) == "unknown")
}
