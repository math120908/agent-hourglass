import UsageCore
import Foundation
import os

/// Discovers the Antigravity Google OAuth client secret at runtime by scanning installed
/// Antigravity/agy binaries for `GOCSPX-` candidates and probing Google for the one it accepts.
///
/// The secret is never committed: it is read from installed binaries, held only as `Secret`, and
/// cached in a dedicated Keychain service (`cc.kuoc.agent-hourglass.oauth-client`) that account
/// cleanup never lists. Discovery runs at most once per app launch, again after `invalidate()` or a
/// transient probe failure; a later launch reads the cache.
///
/// Reference enumeration mirrors CodexBar `AntigravityOAuthCredentialsStore.swift`
/// `candidateOAuthClientArtifactURLs` at `5f93dc3`.
public final class AntigravityClientDiscovery: GoogleOAuthClientSource, @unchecked Sendable {
    public static let cacheService = "cc.kuoc.agent-hourglass.oauth-client"
    static let cacheID = AccountID(rawValue: "google-client:antigravity")!

    /// Bundle ids CodexBar accepts for a renamed Antigravity/Gemini app.
    static let bundleIDs: Set<String> = ["com.google.antigravity", "com.google.antigravity-ide", "com.google.GeminiMacOS"]
    /// CodexBar's relative paths inside an Antigravity app bundle (copied verbatim, `5f93dc3`).
    static let relativePaths = [
        "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
        "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_x64",
        "Contents/Resources/app/extensions/antigravity/bin/language_server_macos",
        "Contents/Resources/app/out/main.js",
        "Contents/Resources/bin/language_server",
        "Contents/Resources/bin/language_server_macos",
        // Gemini.app is a single native binary with no Electron artifacts.
        "Contents/MacOS/Gemini",
    ]

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "AntigravityClientDiscovery")

    private let oauth: GoogleOAuth
    private let cache: any CredentialStoring
    private let files: [URL]

    private let lock = NSLock()
    private var cachedClient: GoogleOAuthClient?
    private var discoveryAttempted = false
    private var inFlight: Task<GoogleOAuthClient, Error>?

    public init(
        oauth: GoogleOAuth,
        cache: any CredentialStoring = CredentialStore(service: AntigravityClientDiscovery.cacheService),
        files: [URL] = AntigravityClientDiscovery.defaultFiles()
    ) {
        self.oauth = oauth
        self.cache = cache
        self.files = files
    }

    // MARK: - File discovery

    public static func defaultFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        defaultFiles(
            home: home,
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
            ]
        )
    }

    static func defaultFiles(home: URL, applicationDirectories: [URL]) -> [URL] {
        let fm = FileManager.default
        var bundles: [URL] = []
        for dir in applicationDirectories {
            bundles.append(dir.appendingPathComponent("Antigravity.app", isDirectory: true))
            let apps = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for app in apps where app.pathExtension == "app" {
                if let id = bundleIdentifier(of: app), bundleIDs.contains(id) { bundles.append(app) }
            }
        }
        var out: [URL] = []
        for bundle in deduped(bundles) {
            for rel in relativePaths { out.append(bundle.appendingPathComponent(rel)) }
        }
        out.append(home.appendingPathComponent(".local/bin/agy"))
        return deduped(out)
    }

    static func bundleIdentifier(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return obj["CFBundleIdentifier"] as? String
    }

    private static func deduped(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    // MARK: - Secret scanning

    /// `GOCSPX-[A-Za-z0-9_-]{28}` byte matches (CodexBar's exact length; a greedy range would
    /// swallow adjacent bytes and never yield the real secret), de-duplicated in first-seen order.
    /// Compares the mapped bytes in place: the language_server binaries are 100 MB+, so no copy.
    static func candidates(in data: Data) -> [String] {
        let prefix: [UInt8] = Array("GOCSPX-".utf8)
        let length = prefix.count + 28
        func isTail(_ b: UInt8) -> Bool {
            (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
                || b == 0x5F || b == 0x2D // '_' '-'
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [String] in
            var out: [String] = []
            var seen = Set<String>()
            var i = 0
            while i + length <= raw.count {
                var k = 0
                while k < prefix.count, raw[i + k] == prefix[k] { k += 1 }
                guard k == prefix.count else { i += 1; continue }
                var j = i + prefix.count
                while j < i + length, isTail(raw[j]) { j += 1 }
                guard j == i + length else { i += 1; continue }
                let s = String(decoding: UnsafeRawBufferPointer(rebasing: raw[i ..< i + length]), as: UTF8.self)
                if seen.insert(s).inserted { out.append(s) }
                i += length
            }
            return out
        }
    }

    /// Scans `files` for candidate secrets. Returns distinct candidates in first-seen order, each
    /// tagged with the file name it came from, and the number of trusted files actually read.
    /// Runs off the main actor (blocking mapped reads).
    private func scan() -> (candidates: [(secret: String, file: String)], filesRead: Int) {
        let idBytes = Data(GoogleOAuth.antigravityClientID.utf8)
        var out: [(secret: String, file: String)] = []
        var seen = Set<String>()
        var filesRead = 0
        for url in files {
            guard let data = Self.trustedData(at: url) else { continue }
            filesRead += 1
            guard data.range(of: idBytes) != nil else { continue }
            for candidate in Self.candidates(in: data) where seen.insert(candidate).inserted {
                out.append((candidate, url.lastPathComponent))
            }
        }
        return (out, filesRead)
    }

    /// Reads a file only when it is a regular file owned by root or the current user and not
    /// group/world-writable (mirrors `CodexAuthSource`'s trust check), else nil.
    static func trustedData(at url: URL) -> Data? {
        let fm = FileManager.default
        let resolved = url.resolvingSymlinksInPath()
        guard let attrs = try? fm.attributesOfItem(atPath: resolved.path) else { return nil }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777
        guard owner == 0 || owner == getuid(), mode & 0o022 == 0 else { return nil }
        return try? Data(contentsOf: resolved, options: .alwaysMapped)
    }

    // MARK: - Client resolution

    public func client() async throws -> GoogleOAuthClient {
        let task: Task<GoogleOAuthClient, Error> = lock.withLock {
            if let c = cachedClient { return Task { c } }
            if let t = inFlight { return t }
            let t = Task { try await self.resolve() }
            inFlight = t
            return t
        }
        lock.withLock { _onEnter }?()
        return try await task.value
    }

    /// Test seam: runs once per `client()` call, after it has joined or started resolution.
    private var _onEnter: (@Sendable () -> Void)?
    var onEnter: (@Sendable () -> Void)? {
        get { lock.withLock { _onEnter } }
        set { lock.withLock { _onEnter = newValue } }
    }

    private func resolve() async throws -> GoogleOAuthClient {
        defer { lock.withLock { inFlight = nil } }

        if let c = (lock.withLock { cachedClient }) { return c }

        // Keychain cache: a secret Google already accepted. No network, no file read.
        let cached: Credential?
        do {
            cached = try cache.read(Self.cacheID)
        } catch {
            Self.log.error("cache read failed")
            cached = nil
        }
        if let cred = cached {
            let client = GoogleOAuthClient(
                clientID: cred.remoteAccountID ?? GoogleOAuth.antigravityClientID,
                secret: cred.access
            )
            lock.withLock { cachedClient = client }
            Self.log.info("antigravity client from keychain")
            return client
        }

        // Discovery, at most once per launch.
        let proceed: Bool = lock.withLock {
            if discoveryAttempted { return false }
            discoveryAttempted = true
            return true
        }
        guard proceed else {
            Self.log.info("discovery already failed this launch")
            throw GoogleOAuthError.clientUnavailable
        }

        let scanned = await Task.detached(priority: .utility) { [self] in scan() }.value
        do {
            for found in scanned.candidates.prefix(4) {
                let candidate = GoogleOAuthClient(secret: Secret(found.secret))
                if try await oauth.probe(candidate) {
                    do {
                        try cache.write(
                            Credential(
                                kind: .google,
                                access: Secret(found.secret),
                                refresh: nil,
                                expiresAt: nil,
                                refreshExpiresAt: nil,
                                scopes: [],
                                remoteAccountID: candidate.clientID
                            ),
                            for: Self.cacheID,
                            label: "Google OAuth client (Antigravity)"
                        )
                    } catch {
                        Self.log.error("cache write failed")
                    }
                    lock.withLock { cachedClient = candidate }
                    // file name only, never the secret.
                    Self.log.info("discovered from \(found.file, privacy: .public)")
                    return candidate
                }
            }
        } catch let error as ProviderError where Self.isTransient(error) {
            // Offline, 429 or 5xx is no verdict on the candidates: the next attempt discovers again.
            lock.withLock { discoveryAttempted = false }
            Self.log.error("probe failed: \(error.description, privacy: .public)")
            throw error
        } catch {
            Self.notFound(scanned)
            throw GoogleOAuthError.clientUnavailable
        }
        Self.notFound(scanned)
        throw GoogleOAuthError.clientUnavailable
    }

    private static func isTransient(_ error: ProviderError) -> Bool {
        switch error {
        case .transport, .rateLimited: true
        case let .http(status, _, _): status >= 500
        default: false
        }
    }

    private static func notFound(_ scanned: (candidates: [(secret: String, file: String)], filesRead: Int)) {
        log.error("not found (files=\(scanned.filesRead, privacy: .public) candidates=\(scanned.candidates.count, privacy: .public))")
    }

    /// Called after Google rejected the secret: the next `client()` discovers again (once per rejection).
    public func invalidate() async {
        try? cache.delete(Self.cacheID)
        lock.withLock {
            cachedClient = nil
            discoveryAttempted = false
        }
    }
}
