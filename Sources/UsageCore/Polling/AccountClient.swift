import Foundation
import os

public enum FetchOutcome: Sendable, Equatable {
    case success(UsageSnapshot)
    case failure(AccountStatus)
}

/// Owns one account's credential, refresh, and 429 backoff.
public actor AccountClient {
    static let proactiveWindow: TimeInterval = 300
    private static let log = Logger(subsystem: "cc.kuoc.claude-usage", category: "AccountClient")

    public let id: AccountID
    private let provider: UsageProvider
    private let http: HTTPClient
    private let store: CredentialStoring
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let lock = RefreshLock()
    private let label: String

    public private(set) var status: AccountStatus = .noData
    public private(set) var nextEarliestFetch: Date = .distantPast
    public private(set) var lastSnapshot: UsageSnapshot?
    /// The rotated credential could not be written to the Keychain (chip "Can't save credential").
    public private(set) var saveFailed = false

    private var credential: Credential?
    private var backoff: Backoff

    public init(
        id: AccountID,
        provider: UsageProvider,
        http: HTTPClient,
        store: CredentialStoring,
        clock: any Clock<Duration>,
        now: @escaping @Sendable () -> Date,
        backoff: Backoff = Backoff(),
        label: String? = nil
    ) {
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
        if saveFailed, let credential { persist(credential) }
        do {
            var cred = try currentCredential()
            if let exp = cred.expiresAt, exp.timeIntervalSince(now()) < Self.proactiveWindow {
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
            snap.accountID = id
            backoff.reset()
            lastSnapshot = snap
            status = saveFailed ? .stale : .fresh
            nextEarliestFetch = now().addingTimeInterval(Backoff.seconds(provider.minimumInterval))
            return .success(snap)
        } catch {
            return .failure(fail(error))
        }
    }

    private func currentCredential() throws -> Credential {
        if let credential { return credential }
        guard let stored = try store.read(id) else { throw ProviderError.invalidGrant }
        credential = stored
        return stored
    }

    /// Refresh `stale` unless someone already rotated it. Joins any in-flight refresh.
    private func refresh(replacing stale: Credential) async throws -> Credential {
        if let credential, credential.access != stale.access { return credential }
        let provider = provider, http = http
        return try await lock.refresh { [self] in
            guard let fresh = try await provider.refresh(credential: stale, http: http) else { return stale }
            await self.adopt(fresh)
            return fresh
        }
    }

    /// Persist first, then hold in memory. A failed write keeps the new credential; the old one is gone.
    private func adopt(_ fresh: Credential) {
        persist(fresh)
        credential = fresh
    }

    private func persist(_ c: Credential) {
        do {
            try store.write(c, for: id, label: label)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func fail(_ error: any Error) -> AccountStatus {
        let s: AccountStatus
        switch error as? ProviderError {
        case .invalidGrant, .unauthorized:
            s = .needsLogin
        case let .rateLimited(retryAfter):
            let at = backoff.next(retryAfter: retryAfter, now: now())
            Self.log.debug("429 #\(self.backoff.consecutive429) for \(self.id.rawValue, privacy: .public)")
            nextEarliestFetch = at
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
