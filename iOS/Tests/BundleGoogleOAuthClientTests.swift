import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

/// Runs `body` with a temp `.bundle` whose Info.plist holds `AHGoogleClientSecret` (absent when nil), then
/// deletes it. Secret-shaped values are built at runtime so no `GOCSPX-…` literal enters the repo (secret-scan rule).
private func withFakeBundle(secret: String?, _ body: (Bundle) async throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-\(UUID().uuidString).bundle")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": "cc.kuoc.test.fake", "CFBundlePackageType": "BNDL"]
    if let secret { info["AHGoogleClientSecret"] = secret }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: dir.appendingPathComponent("Info.plist"))
    try await body(try #require(Bundle(url: dir)))
}

private let validSecret = "GOCSPX-" + String(repeating: "a", count: 28)

private func expectUnavailable(secret: String?) async throws {
    try await withFakeBundle(secret: secret) { bundle in
        #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle) == false)
        await #expect(throws: GoogleOAuthError.clientUnavailable) {
            try await BundleGoogleOAuthClient(bundle: bundle).client()
        }
    }
}

@Test func emptySecretIsNotConfigured() async throws { try await expectUnavailable(secret: "") }

@Test func missingSecretIsNotConfigured() async throws { try await expectUnavailable(secret: nil) }

@Test func unexpandedSecretIsNotConfigured() async throws { try await expectUnavailable(secret: "$(GOOGLE_AG_CLIENT_SECRET)") }

@Test func wrongShapeSecretIsNotConfigured() async throws { try await expectUnavailable(secret: "nope") }

@Test func validSecretRoundTrips() async throws {
    try await withFakeBundle(secret: validSecret) { bundle in
        #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle))
        let client = try await BundleGoogleOAuthClient(bundle: bundle).client()
        #expect(client.secret.reveal() == validSecret)
        #expect(client.clientID == GoogleOAuth.antigravityClientID)
    }
}
