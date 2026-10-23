import UsageCore
import Foundation

/// Borrows tokens from an existing `gh` login. gh runs only from a fixed trusted path,
/// with a fixed environment; the token is read from stdout into a `Secret` and never
/// placed in any child's argv or env. Tokens are cached in memory for the process lifetime.
public struct GhTokenSource: Sendable {
    public let candidates: [String]
    public let timeout: Duration
    private let cache = TokenCache()

    public init(candidates: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"], timeout: Duration = .seconds(5)) {
        self.candidates = candidates
        self.timeout = timeout
    }

    /// github.com logins from `gh auth status --hostname github.com`.
    public func logins() async throws -> [String] {
        let (_, out) = try await run(["auth", "status", "--hostname", "github.com"])
        return Self.parseLogins(String(decoding: out, as: UTF8.self))
    }

    /// Cached token for `login`; spawns gh only on a cache miss.
    public func token(for login: String) async throws -> Secret {
        if let cached = cache.get(login) { return cached }
        let (status, out) = try await run(["auth", "token", "--user", login])
        guard status == 0, let token = Self.parseToken(out) else { throw GhError.loginRemoved }
        cache.set(login, token)
        return token
    }

    /// Drops the cached token (call on a 401, then re-read once).
    public func invalidate(_ login: String) { cache.remove(login) }

    static func parseLogins(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            guard line.contains("github.com"), let r = line.range(of: "account ") else { return nil }
            return line[r.upperBound...].split(separator: " ").first.map(String.init)
        }
    }

    static func parseToken(_ data: Data) -> Secret? {
        let prefixes = ["gho_", "ghp_", "ghu_", "ghs_", "ghr_", "github_pat_"]
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard let last = lines.map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }),
              prefixes.contains(where: last.hasPrefix) else { return nil }
        return Secret(last)
    }

    /// First existing candidate, symlinks resolved; throws `.untrusted` if its owner is not
    /// root or the current user, or it is group/world-writable.
    func trustedPath() throws -> String {
        let fm = FileManager.default
        for candidate in candidates where fm.fileExists(atPath: candidate) {
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            let attrs = try fm.attributesOfItem(atPath: resolved)
            let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value
            let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777
            guard let owner, owner == 0 || owner == getuid(), mode & 0o022 == 0,
                  fm.isExecutableFile(atPath: resolved) else { throw GhError.untrusted }
            return resolved
        }
        throw GhError.missing
    }

    private func run(_ args: [String]) async throws -> (Int32, Data) {
        let path = try trustedPath()
        let c = timeout.components
        let seconds = Double(c.seconds) + Double(c.attoseconds) / 1e18
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                cont.resume(with: Result { try Self.runBlocking(path, args, seconds) })
            }
        }
    }

    private static func runBlocking(_ path: String, _ args: [String], _ seconds: Double) throws -> (Int32, Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let env = ProcessInfo.processInfo.environment
        p.environment = ["HOME": env["HOME"] ?? NSHomeDirectory(), "USER": env["USER"] ?? NSUserName(), "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { throw GhError.missing }
        let box = DataBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if exited.wait(timeout: .now() + seconds) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            throw GhError.timeout
        }
        guard readDone.wait(timeout: .now() + seconds) == .success else { throw GhError.timeout }
        return (p.terminationStatus, box.data)
    }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

private final class TokenCache: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: Secret] = [:]
    func get(_ k: String) -> Secret? { lock.withLock { tokens[k] } }
    func set(_ k: String, _ v: Secret) { lock.withLock { tokens[k] = v } }
    func remove(_ k: String) { lock.withLock { _ = tokens.removeValue(forKey: k) } }
}

extension GhTokenSource: CopilotTokenSource {}
