import Foundation
import UsageCore

/// Composition root shared by the iOS app and widget: the single place clients are built.
struct UsageEnvironment: Sendable {
    /// `<container>/cc.kuoc.agent-hourglass`.
    let directory: URL
    let registry: AccountRegistry
    let store: CredentialStore
    let shared: SharedAccountState
    let http: HTTPClient
    /// Whether this build carries the Google secret. Without it Google accounts are unsupported,
    /// so one left over from a dev build is hidden instead of shown as a dead card.
    var googleConfigured: Bool = BundleGoogleOAuthClient.isConfigured()

    static func make(base: URL, service: String, accessGroup: String) throws -> UsageEnvironment {
        let dir = try AppSupport.directory(base: base)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dir.path
        )
        return UsageEnvironment(
            directory: dir,
            registry: AccountRegistry(directory: dir),
            store: CredentialStore(service: service, accessGroup: accessGroup),
            shared: .inDirectory(dir),
            http: HTTPClient()
        )
    }

    static func live() -> UsageEnvironment {
        do {
            return try make(base: AppGroup.containerURL, service: CredentialStore.service, accessGroup: AppGroup.keychainAccessGroup)
        } catch {
            preconditionFailure("UsageEnvironment: \(error)")
        }
    }

    /// Claude (or no kind), Codex and Google. iOS v1 has no Copilot: returns nil for a Copilot id.
    /// Google refreshes with the bundle's dev-only secret (SPIKE); returns nil when the build has none.
    func makeClient(_ id: AccountID) -> AccountClient? {
        let provider: UsageProvider
        switch id.kind ?? .claude {
        case .claude: provider = ClaudeProvider()
        case .codex: provider = CodexProvider(auth: nil)
        case .copilot: return nil
        case .google:
            guard googleConfigured else { return nil }
            provider = GoogleProvider(client: BundleGoogleOAuthClient())
        }
        return AccountClient(
            id: id,
            provider: provider,
            http: http,
            store: store,
            clock: ContinuousClock(),
            now: { Date() },
            shared: shared
        )
    }
}
