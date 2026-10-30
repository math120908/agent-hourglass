import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

/// A temp `.bundle` directory whose Info.plist holds `AHGoogleClientSecret` (absent when nil).
/// Secret-shaped values are built at runtime so no `GOCSPX-…` literal enters the repo (secret-scan rule).
private func fakeBundle(secret: String?) throws -> Bundle {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-\(UUID().uuidString).bundle")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": "cc.kuoc.test.fake", "CFBundlePackageType": "BNDL"]
    if let secret { info["AHGoogleClientSecret"] = secret }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: dir.appendingPathComponent("Info.plist"))
    return try #require(Bundle(url: dir))
}

private let validSecret = "GOCSPX-" + String(repeating: "a", count: 28)

@Test func emptySecretIsNotConfigured() async throws {
    let bundle = try fakeBundle(secret: "")
    #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle) == false)
    await #expect(throws: GoogleOAuthError.clientUnavailable) {
        try await BundleGoogleOAuthClient(bundle: bundle).client()
    }
}

@Test func missingSecretIsNotConfigured() async throws {
    let bundle = try fakeBundle(secret: nil)
    #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle) == false)
    await #expect(throws: GoogleOAuthError.clientUnavailable) {
        try await BundleGoogleOAuthClient(bundle: bundle).client()
    }
}

@Test func unexpandedSecretIsNotConfigured() throws {
    #expect(BundleGoogleOAuthClient.isConfigured(bundle: try fakeBundle(secret: "$(GOOGLE_AG_CLIENT_SECRET)")) == false)
}

@Test func wrongShapeSecretIsNotConfigured() async throws {
    let bundle = try fakeBundle(secret: "nope")
    #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle) == false)
    await #expect(throws: GoogleOAuthError.clientUnavailable) {
        try await BundleGoogleOAuthClient(bundle: bundle).client()
    }
}

@Test func validSecretRoundTrips() async throws {
    let bundle = try fakeBundle(secret: validSecret)
    #expect(BundleGoogleOAuthClient.isConfigured(bundle: bundle))
    let client = try await BundleGoogleOAuthClient(bundle: bundle).client()
    #expect(client.secret.reveal() == validSecret)
    #expect(client.clientID == GoogleOAuth.antigravityClientID)
}
