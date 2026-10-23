import Foundation
import os

public enum FetchOutcome: Sendable, Equatable {
    case success(UsageSnapshot)
    case failure(AccountStatus)
}

/// Owns one account's credential, refresh, and 429 backoff.
public actor AccountClient {
    static let proactiveWindow: TimeInterval = 300
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "AccountClient")

    public let id: AccountID
    private let provider: UsageProvider
    private let http: HTTPClient
    private let store: CredentialStoring
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let lock = RefreshLock()
    private let label: String
    /// Copilot only: borrows the token from gh for `login`. No Keychain item.
    private let gh: (source: any CopilotTokenSource, login: String)?
    /// Claude Code (local) only: re-reads Claude Code's Keychain item on every fetch. Never refreshes or writes.
    private let claudeCode: ClaudeCodeLoginReading?
    /// iOS app and widget: App Group cache and backoff. nil on the Mac (no files touched).
    private let shared: SharedAccountState?

    public private(set) var status: AccountStatus = .noData
    public private(set) var nextEarliestFetch: Date = .distantPast
    public private(set) var lastSnapshot: UsageSnapshot?
    /// The rotated credential could not be written to the Keychain (chip "Can't save credential").
    public private(set) var saveFailed = false

    private var credential: Credential?
    private var backoff: Backoff
    /// Set when the account is removed. A fetch still in flight then writes nothing:
    /// no Keychain item, no shared snapshot, no shared backoff.
    public private(set) var isCancelled = false

    /// Called by `Poller.remove` before the account's Keychain item and files are deleted.
    public func cancel() { isCancelled = true }

    public init(
        id: AccountID,
        provider: UsageProvider,
        http: HTTPClient,
        store: CredentialStoring,
        clock: any Clock<Duration>,
        now: @escaping @Sendable () -> Date,
        backoff: Backoff = Backoff(),
        label: String? = nil,
        tokenSource: (any CopilotTokenSource)? = nil,
        login: String? = nil,
        claudeCode: ClaudeCodeLoginReading? = nil,
        shared: SharedAccountState? = nil
    ) {
        self.shared = shared
        self.claudeCode = claudeCode
        self.gh = tokenSource.flatMap { src in login.map { (src, $0) } }
        self.id = id
        self.label = label ?? AccountService.keychainLabel(kind: id.kind ?? .claude, number: 1)
        self.provider = provider
        self.http = http
        self.store = store
        self.clock = clock
        self.now = now
        self.backoff = backoff
    }

    public func fetch() async -> FetchOutcome {
        if status == .needsLogin { return .failure(.needsLogin) }
        if status == .claudeCodeDenied { return .failure(.claudeCodeDenied) }
        if let shared, let gated = sharedGate(shared) { return gated }
        if let claudeCode { return await fetchClaudeCode(claudeCode) }
        if let gh { return await fetchCopilot(gh.source, login: gh.login) }
        if (provider as? CodexProvider)?.isBorrowed == true { return await fetchBorrowed() }
        if saveFailed, let credential {
            if let shared { persistShared(credential, shared) } else { persist(credential) }
        }
        do {
            var cred = try currentCredential()
            if let exp = cred.expiresAt, exp.timeIntervalSince(now()) < Self.proactiveWindow,
               provider.kind != .codex || CodexDeviceAuth.shouldRefresh(cred, now: now()) {
                cred = try await refresh(replacing: cred)
            }
            var snap: UsageSnapshot
            do {
                snap = try await provider.fetch(credential: cred, http: http)
            } catch ProviderError.unauthorized {
                cred = try await refresh(replacing: cred)
                do {
                    snap = try await provider.fetch(credential: cred, http: http)
                } catch ProviderError.unauthorized {
                    throw ProviderError.invalidGrant
                }
            }
            return succeed(snap)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Claude Code (local): fresh read each poll, token in memory for this request only.
    /// Near expiry or 401 shows "run `claude`"; no refresh and no retry until the next poll.
    private func fetchClaudeCode(_ reader: ClaudeCodeLoginReading) async -> FetchOutcome {
        let login: ClaudeCodeLogin
        do {
            login = try reader.read()
        } catch let e as ClaudeCodeKeychainError {
            let s: AccountStatus = switch e {
            case .notFound, .malformed: .claudeCodeNotSignedIn
            case .userCanceled, .interactionNotAllowed: .claudeCodeDenied
            case .other: .stale
            }
            status = s
            return .failure(s)
        } catch {
            return .failure(fail(error))
        }
        if login.isExpired(now: now()) {
            status = .claudeCodeExpired
            return .failure(.claudeCodeExpired)
        }
        let cred = Credential(kind: .claude, access: login.access, refresh: nil, expiresAt: login.expiresAt, refreshExpiresAt: nil, scopes: [])
        do {
            return succeed(try await provider.fetch(credential: cred, http: http))
        } catch ProviderError.unauthorized {
            status = .claudeCodeExpired
            return .failure(.claudeCodeExpired)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Token cached by gh; a 401 drops it, re-reads once and retries once.
    private func fetchCopilot(_ src: any CopilotTokenSource, login: String) async -> FetchOutcome {
        do {
            var snap: UsageSnapshot
            do {
                snap = try await provider.fetch(credential: Self.copilotCredential(try await src.token(for: login)), http: http)
            } catch ProviderError.unauthorized {
                src.invalidate(login)
                do {
                    snap = try await provider.fetch(credential: Self.copilotCredential(try await src.token(for: login)), http: http)
                } catch ProviderError.unauthorized {
                    throw ProviderError.invalidGrant
                }
            }
            return succeed(snap)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Codex: the provider reads ~/.codex/auth.json itself and handles the 401 re-read. No Keychain.
    private func fetchBorrowed() async -> FetchOutcome {
        do {
            return succeed(try await provider.fetch(credential: CodexProvider.borrowed, http: http))
        } catch {
            let s = fail(error)
            Self.log.info("codex fetch failed: \(String(describing: type(of: error)), privacy: .public) status=\(String(describing: s), privacy: .public)")
            return .failure(s)
        }
    }

    /// Serves a fresh shared snapshot or honours the shared backoff without touching the network.
    private func sharedGate(_ shared: SharedAccountState) -> FetchOutcome? {
        let t = now()
        let cached = shared.cache.read(id)
        let interval = Backoff.seconds(provider.minimumInterval)
        if let cached, cached.fetchedAt <= t, t.timeIntervalSince(cached.fetchedAt) < interval {
            lastSnapshot = cached
            status = .fresh
            nextEarliestFetch = cached.fetchedAt.addingTimeInterval(interval)
            return .success(cached)
        }
        // While this process holds the only copy of a rotated credential, its own retry is not gated.
        if !(saveFailed && credential != nil), let next = shared.backoff.nextAllowedFetch(id, now: t), t < next {
            lastSnapshot = cached ?? lastSnapshot
            nextEarliestFetch = next
            status = .rateLimited(retryAt: next)
            return .failure(.rateLimited(retryAt: next))
        }
        return nil
    }

    private func writeSharedBackoff() {
        guard let shared, !isCancelled else { return }
        do {
            try shared.backoff.setNextAllowedFetch(nextEarliestFetch, for: id)
        } catch {
            Self.log.error("shared backoff write failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    static func copilotCredential(_ token: Secret) -> Credential {
        Credential(kind: .copilot, access: token, refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
    }

    private func succeed(_ s: UsageSnapshot) -> FetchOutcome {
        var snap = s
        snap.accountID = id
        backoff.stepDown()
        lastSnapshot = snap
        status = saveFailed ? .stale : .fresh
        let wait = max(Backoff.seconds(provider.minimumInterval), backoff.levelDelay ?? 0)
        nextEarliestFetch = now().addingTimeInterval(wait)
        if let shared, !isCancelled {
            do {
                try shared.cache.write(snap)
            } catch {
                Self.log.error("shared cache write failed: \(String(describing: type(of: error)), privacy: .public)")
            }
            writeSharedBackoff()
        }
        return .success(snap)
    }

    /// Owned Codex with no Keychain item has never signed in; other kinds lost their login.
    private var missingCredential: any Error {
        provider.kind == .codex ? CodexAuthError.missing : ProviderError.invalidGrant
    }

    private func currentCredential() throws -> Credential {
        if shared != nil {
            // No cache across the refresh boundary: the other process may have rotated it.
            if saveFailed, let credential { return credential }
            guard let stored = try store.read(id) else { throw missingCredential }
            credential = stored
            return stored
        }
        if let credential { return credential }
        guard let stored = try store.read(id) else { throw missingCredential }
        credential = stored
        return stored
    }

    /// Refresh `stale` unless someone already rotated it. Joins any in-flight refresh.
    private func refresh(replacing stale: Credential) async throws -> Credential {
        if let credential, credential.access != stale.access { return credential }
        let provider = provider, http = http
        if let shared {
            return try await lock.refresh { [self] in
                try await shared.lock.withLock { try await self.refreshLocked(replacing: stale, shared: shared) }
            }
        }
        return try await lock.refresh { [self] in
            guard let fresh = try await provider.refresh(credential: stale, http: http) else { return stale }
            await self.adopt(fresh)
            return fresh
        }
    }

    /// Runs under the cross-process lock: re-read the store, refresh only if nobody else did, persist before returning.
    private func refreshLocked(replacing stale: Credential, shared: SharedAccountState) async throws -> Credential {
        let base: Credential
        if saveFailed, let credential {
            base = credential
        } else if let stored = try store.read(id) {
            if stored.access != stale.access {
                credential = stored
                return stored
            }
            base = stored
        } else {
            base = stale
        }
        do {
            guard let fresh = try await provider.refresh(credential: base, http: http) else { return base }
            persistShared(fresh, shared)
            credential = fresh
            return fresh
        } catch ProviderError.invalidGrant {
            // Another process may have rotated the token between our read and the refresh.
            if let stored = try? store.read(id), stored.access != base.access {
                credential = stored
                return stored
            }
            throw ProviderError.invalidGrant
        }
    }

    /// Write, retry once; if both fail, block the other process from refreshing with a stale refresh token.
    private func persistShared(_ c: Credential, _ shared: SharedAccountState) {
        guard !isCancelled else { return }
        persist(c)
        if saveFailed { persist(c) }
        guard saveFailed else { return }
        Self.log.error("credential save failed twice kind=\(self.id.kind?.rawValue ?? "unknown", privacy: .public)")
        do {
            try shared.backoff.setNextAllowedFetch(now().addingTimeInterval(60), for: id)
        } catch {
            Self.log.error("shared backoff write failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Persist first, then hold in memory. A failed write keeps the new credential; the old one is gone.
    private func adopt(_ fresh: Credential) {
        persist(fresh)
        credential = fresh
    }

    private func persist(_ c: Credential) {
        guard !isCancelled else { return }
        do {
            try store.write(c, for: id, label: label)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func fail(_ error: any Error) -> AccountStatus {
        let s: AccountStatus
        if let gh = error as? GhError {
            switch gh {
            case .missing, .untrusted: s = .ghMissing
            case .loginRemoved: s = .ghLoginRemoved
            case .timeout: s = .stale
            }
            status = s
            return s
        }
        if error is CodexAuthError {
            status = .codexNotSignedIn
            return .codexNotSignedIn
        }
        switch error as? ProviderError {
        case .invalidGrant, .unauthorized:
            s = .needsLogin
        case let .rateLimited(retryAfter):
            let at = backoff.next(retryAfter: retryAfter, now: now())
            Self.log.info("429 #\(self.backoff.consecutive429) for \(self.id.kind?.rawValue ?? "unknown", privacy: .public) retryAfter=\(retryAfter.map { "\($0)" } ?? "none", privacy: .public) wait=\(Int(at.timeIntervalSince(self.now())), privacy: .public)s")
            nextEarliestFetch = at
            writeSharedBackoff()
            s = .rateLimited(retryAt: at)
        case .transport:
            s = .offline
        case .schema:
            s = .schemaError
        default:
            s = .stale
        }
        status = s
        return s
    }
}
