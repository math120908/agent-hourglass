import Foundation
import UsageCore

/// SPIKE, dev builds only: the Google OAuth client secret from the `AHGoogleClientSecret` Info.plist key.
/// The value comes from the untracked `iOS/Config/GoogleOAuth.local.xcconfig` (`make -C iOS google-config`);
/// `testflight.sh` refuses to archive while it is set, so it never ships. Unset → Google is not offered.
struct BundleGoogleOAuthClient: GoogleOAuthClientSource {
    static let infoKey = "AHGoogleClientSecret"

    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    static func isConfigured(bundle: Bundle = .main) -> Bool { secret(in: bundle) != nil }

    func client() async throws -> GoogleOAuthClient {
        guard let secret = Self.secret(in: bundle) else { throw GoogleOAuthError.clientUnavailable }
        return GoogleOAuthClient(secret: Secret(secret))
    }

    /// Nothing is cached, so a rejected secret has nothing to drop; a new xcconfig needs a rebuild.
    func invalidate() async {}

    private static func secret(in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: infoKey) as? String,
              value.hasPrefix("GOCSPX-"), value.count > "GOCSPX-".count
        else { return nil }
        return value
    }
}
