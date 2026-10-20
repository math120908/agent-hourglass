import Testing
@testable import UsageCore

@Test func versionIsSet() {
    #expect(UsageCoreVersion.string == "0.1.0")
}
