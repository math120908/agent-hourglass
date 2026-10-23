import UsageCore
import Foundation

extension ClaudePKCEFlow {
    static func redirectURI(port: UInt16) -> String { "http://localhost:\(port)/callback" }

    public func run(
        loginHint: String?,
        open: (URL) -> Void,
        expectedRemoteID: String? = nil,
    ) async throws -> (Credential, remoteAccountID: String) {
        let pkce = PKCE.make()
        let listener = try await LoopbackListener.bind()
        let redirect = Self.redirectURI(port: listener.port)
        let code: String
        do {
            open(authorizeURL(pkce: pkce, redirectURI: redirect, loginHint: loginHint))
            code = try await listener.awaitCallback(expectedState: pkce.state)
        } catch {
            await listener.close()
            throw error
        }
        let (cred, remoteID) = try await exchange(code: code, pkce: pkce, redirectURI: redirect)
        if let expectedRemoteID, expectedRemoteID != remoteID { throw AuthError.differentAccount }
        return (cred, remoteID)
    }
}
