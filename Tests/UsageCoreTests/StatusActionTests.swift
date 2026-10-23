import XCTest
@testable import UsageCore

final class StatusActionTests: XCTestCase {
    func testEveryStatusMaps() {
        let d = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(StatusAction.make(.fresh), StatusAction.none)
        XCTAssertEqual(StatusAction.make(.noData), StatusAction.none)
        XCTAssertEqual(StatusAction.make(.stale), .stale)
        XCTAssertEqual(StatusAction.make(.needsLogin), .signIn)
        XCTAssertEqual(StatusAction.make(.codexNotSignedIn), .signIn)
        XCTAssertEqual(StatusAction.make(.ghMissing), .signIn)
        XCTAssertEqual(StatusAction.make(.ghLoginRemoved), .signIn)
        XCTAssertEqual(StatusAction.make(.claudeCodeNotSignedIn), .signIn)
        XCTAssertEqual(StatusAction.make(.claudeCodeExpired), .signIn)
        XCTAssertEqual(StatusAction.make(.claudeCodeDenied), .signIn)
        XCTAssertEqual(StatusAction.make(.rateLimited(retryAt: d)), .rateLimited(retryAt: d))
        XCTAssertEqual(StatusAction.make(.schemaError), .formatChanged)
        XCTAssertEqual(StatusAction.make(.offline), .offline)
    }
}
