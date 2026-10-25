import Foundation
import Testing
@testable import UsageCore

struct AccountNameTests {
    let base = AccountServiceTests()

    func cred(_ email: String?) -> Credential {
        Credential(kind: .claude, access: Secret("t"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [], accountEmail: email)
    }

    @Test func emailIsDefaultName() async throws {
        let (svc, _, registry) = try base.make([])
        try await svc.addClaude(credential: cred("a@x.com"), remoteID: "a")
        #expect(await registry.accounts().first?.displayName == "a@x.com")
    }

    @Test func noEmailFallsBackToNumber() async throws {
        let (svc, _, registry) = try base.make([])
        try await svc.addClaude(credential: cred(nil), remoteID: "a")
        #expect(await registry.accounts().first?.displayName == "Claude #1")
    }

    @Test func unrenamedNameUpgradesOnReadd() async throws {
        let (svc, _, registry) = try base.make([])
        try await svc.addClaude(credential: cred(nil), remoteID: "a")
        try await svc.addClaude(credential: cred("a@x.com"), remoteID: "a")
        #expect(await registry.accounts().first?.displayName == "a@x.com")
    }

    @Test func renameSurvivesReadd() async throws {
        let (svc, _, registry) = try base.make([])
        let id = try await svc.addClaude(credential: cred("a@x.com"), remoteID: "a")
        try await registry.rename(id, to: "Work")
        try await svc.addClaude(credential: cred("new@x.com"), remoteID: "a")
        let e = await registry.accounts().first
        #expect(e?.displayName == "Work")
        #expect(e?.nameIsCustom == true)
    }

    @Test func claudeCodeLocalUpgradesThenKeepsRename() async throws {
        let (svc, _, registry) = try base.make([])
        try await svc.addClaudeCodeLocal()
        #expect(await registry.accounts().first?.displayName == "Claude Code")
        try await svc.addClaudeCodeLocal(name: "CK")
        #expect(await registry.accounts().first?.displayName == "CK")
        try await registry.rename(.claudeCodeLocal, to: "Mine")
        try await svc.addClaudeCodeLocal(name: "CK")
        #expect(await registry.accounts().first?.displayName == "Mine")
    }

    @Test func oldRegistryWithoutFlagDecodes() throws {
        let json = """
        {"id":"claude:a","kind":"claude","displayName":"Old","remoteLogin":null,"order":0,"addedAt":"2024-01-01T00:00:00Z","status":"ok"}
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let e = try d.decode(AccountEntry.self, from: Data(json.utf8))
        #expect(e.displayName == "Old")
        #expect(e.nameIsCustom == false)
    }

    @Test func tokenResponseCarriesEmail() throws {
        let body = #"{"access_token":"x","account":{"uuid":"u","email_address":"a@x.com"}}"#
        let (c, id, email) = try ClaudeProvider.decodeTokenResponse(Data(body.utf8), now: Date())
        #expect(id == "u" && email == "a@x.com" && c.accountEmail == "a@x.com")
    }
}
