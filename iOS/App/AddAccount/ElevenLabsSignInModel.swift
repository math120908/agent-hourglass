import Foundation
import Observation
import UsageCore

/// iOS ElevenLabs sign-in logic (mirrors the Mac `ElevenLabsWebLogin` + `addElevenLabs()`): the view
/// polls a non-persistent web view with `probeScript` and feeds each result to `receive(probeResult:)`.
/// The first valid Firebase session is exchanged for a fresh ID token and added. Tokens are never logged.
@MainActor @Observable final class ElevenLabsSignInModel {
    enum Phase: Equatable {
        case browsing
        case finishing
        case done(AccountID)
        case failed(String)
    }

    static let signInURL = URL(string: "https://elevenlabs.io/app/sign-in")!

    /// Async body for `callAsyncJavaScript`: returns a JSON array string of every
    /// `firebase:authUser:*` value from localStorage, falling back to Firebase's IndexedDB store.
    static let probeScript = """
    const out = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && k.startsWith('\(ElevenLabsWebSession.storageKeyPrefix)')) out.push(localStorage.getItem(k));
    }
    if (out.length === 0 && window.indexedDB) {
      try {
        const rows = await new Promise((resolve) => {
          const open = indexedDB.open('firebaseLocalStorageDb');
          open.onupgradeneeded = () => { open.transaction.abort(); resolve([]); };
          open.onerror = () => resolve([]);
          open.onsuccess = () => {
            const db = open.result;
            if (!db.objectStoreNames.contains('firebaseLocalStorage')) { db.close(); resolve([]); return; }
            const req = db.transaction('firebaseLocalStorage', 'readonly').objectStore('firebaseLocalStorage').getAll();
            req.onsuccess = () => { db.close(); resolve(req.result || []); };
            req.onerror = () => { db.close(); resolve([]); };
          };
        });
        for (const r of rows) {
          if (r && typeof r.fbase_key === 'string' && r.fbase_key.startsWith('\(ElevenLabsWebSession.storageKeyPrefix)')) out.push(r.value);
        }
      } catch (e) {}
    }
    return JSON.stringify(out);
    """

    private(set) var phase: Phase = .browsing
    /// Host of the page currently shown, for the read-only bar above the web view.
    var currentHost: String?

    @ObservationIgnored private let refresh: (Credential) async throws -> Credential
    @ObservationIgnored private let add: (Credential) async throws -> AccountID
    @ObservationIgnored private var task: Task<Void, Never>?

    convenience init(app: AppModel) {
        let service = app.service
        let http = app.http
        self.init(
            refresh: { seed in
                guard let cred = try await ElevenLabsProvider().refresh(credential: seed, http: http) else {
                    throw ProviderError.invalidGrant
                }
                return cred
            },
            add: { cred in try await app.add { try await service.addElevenLabs(credential: cred) } },
        )
    }

    init(
        refresh: @escaping (Credential) async throws -> Credential,
        add: @escaping (Credential) async throws -> AccountID,
    ) {
        self.refresh = refresh
        self.add = add
    }

    /// Feed one probe result (the JSON string from `probeScript`). Ignored unless still browsing
    /// and the result holds a signed-in session.
    func receive(probeResult: String?) {
        guard phase == .browsing, let probeResult, let session = ElevenLabsWebSession.parse(probeResult) else { return }
        phase = .finishing
        task = Task { [refresh, add] in
            do {
                let cred = try await refresh(session.seedCredential)
                try Task.checkCancellation()
                let id = try await add(cred)
                guard !Task.isCancelled else { return }
                phase = .done(id)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                if case .failed(let message) = AddFlowState.deviceFailure(error) {
                    phase = .failed(message)
                } else {
                    phase = .failed("Sign-in failed")
                }
            }
        }
    }

    /// Stops any in-flight finish; the sheet is being dismissed.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
