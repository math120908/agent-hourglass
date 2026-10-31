import Foundation

/// The Firebase user that elevenlabs.io keeps in the browser after sign-in.
/// Parsed from the `firebase:authUser:<apiKey>:[DEFAULT]` entry (localStorage or the
/// `firebaseLocalStorageDb` IndexedDB store). Never logged: `refreshToken` is a long-lived secret.
public struct ElevenLabsWebSession: Sendable, Equatable {
    public static let storageKeyPrefix = "firebase:authUser:"

    public let uid: String
    public let email: String?
    public let refreshToken: Secret

    /// Parses the JSON array the sign-in page script returns: each element is one stored
    /// auth-user value, either a JSON object or a JSON-encoded string of one. The first
    /// element with a uid and a refresh token wins; nil when nobody is signed in yet.
    public static func parse(_ json: String) -> ElevenLabsWebSession? {
        guard let items = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else { return nil }
        for item in items {
            if let s = parseUser(item) { return s }
        }
        return nil
    }

    static func parseUser(_ item: Any) -> ElevenLabsWebSession? {
        var obj = item as? [String: Any]
        if obj == nil, let s = item as? String {
            obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        }
        guard let obj,
              let uid = obj["uid"] as? String, !uid.isEmpty,
              let stm = obj["stsTokenManager"] as? [String: Any],
              let rt = stm["refreshToken"] as? String, !rt.isEmpty
        else { return nil }
        let email = (obj["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ElevenLabsWebSession(uid: uid, email: email, refreshToken: Secret(rt))
    }

    /// A refresh-only credential: `ElevenLabsProvider.refresh` mints the ID token from it.
    public var seedCredential: Credential {
        Credential(
            kind: .elevenlabs,
            access: Secret(""),
            refresh: refreshToken,
            expiresAt: Date(timeIntervalSince1970: 0),
            refreshExpiresAt: nil,
            scopes: [],
            remoteAccountID: uid,
            accountEmail: email
        )
    }
}
