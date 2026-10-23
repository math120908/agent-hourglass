import Foundation

/// Borrows the Codex CLI's ChatGPT login from `~/.codex/auth.json`. Strictly read-only:
/// never writes the file, never refreshes. The token is cached in memory; `invalidate()` forces a re-read.
public final class CodexAuthSource: @unchecked Sendable {
    public let path: String
    private let lock = NSLock()
    private var cached: CodexLogin?

    public init(path: String = NSHomeDirectory() + "/.codex/auth.json") { self.path = path }

    public func login() throws -> CodexLogin {
        if let c = lock.withLock({ cached }) { return c }
        let fresh = try read()
        lock.withLock { cached = fresh }
        return fresh
    }

    public func invalidate() { lock.withLock { cached = nil } }

    func read() throws -> CodexLogin {
        let fm = FileManager.default
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard fm.fileExists(atPath: resolved) else { throw CodexAuthError.missing }
        let attrs = try fm.attributesOfItem(atPath: resolved)
        let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777
        guard owner == getuid(), mode & 0o022 == 0 else { throw CodexAuthError.untrusted }
        guard let data = fm.contents(atPath: resolved) else { throw CodexAuthError.missing }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> CodexLogin {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CodexAuthError.malformed
        }
        guard root["auth_mode"] as? String == "chatgpt" else { throw CodexAuthError.notChatGPT }
        guard let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else { throw CodexAuthError.malformed }
        return CodexLogin(access: Secret(access), accountID: account)
    }
}

extension CodexAuthSource: CodexLoginSource {}
