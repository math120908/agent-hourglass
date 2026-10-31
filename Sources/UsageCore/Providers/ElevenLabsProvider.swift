import Foundation

/// ElevenLabs character quota from `GET /v1/user/subscription`, authenticated with a Firebase ID token
/// taken from the web session and refreshed through Google securetoken.
public struct ElevenLabsProvider: UsageProvider {
    public static let subscriptionURL = URL(string: "https://api.us.elevenlabs.io/v1/user/subscription")!
    /// Public Firebase web API key of the `xi-labs` project (shipped in elevenlabs.io JS; not a secret).
    static let firebaseAPIKey = "AIzaSyBSsRE_1Os04-bxpd5JTLIniy3UK4OqKys"
    public static let tokenURL = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseAPIKey)")!

    public let kind: ProviderKind = .elevenlabs
    public let minimumInterval: Duration = .seconds(60)
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    public func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.subscriptionURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await http.send(req, bearer: credential.access)
        // The account id is assigned by the caller; a placeholder keeps decoding pure.
        return try Self.decode(data, accountID: AccountID(kind: .elevenlabs, remoteID: "unknown"), now: now())
    }

    /// Exchanges the Firebase refresh token; the response rotates the refresh token.
    public func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        guard let rt = credential.refresh?.reveal(), !rt.isEmpty else { throw ProviderError.invalidGrant }
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://elevenlabs.io/", forHTTPHeaderField: "Referer")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: rt)]
        req.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let data: Data
        do {
            (data, _) = try await http.send(req, bearer: nil)
        } catch ProviderError.unauthorized {
            throw ProviderError.invalidGrant
        } catch let ProviderError.http(status, _, _) where status == 400 {
            throw ProviderError.invalidGrant
        }
        return try Self.credential(fromTokenResponse: data, now: now(), previous: credential)
    }

    static func credential(fromTokenResponse data: Data, now: Date, previous: Credential) throws -> Credential {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let idToken = obj["id_token"] as? String, !idToken.isEmpty else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        let expiresIn = ClaudeProvider.number(obj["expires_in"]) ?? 3600
        var c = previous
        c.access = Secret(idToken)
        if let rt = obj["refresh_token"] as? String, !rt.isEmpty { c.refresh = Secret(rt) }
        c.expiresAt = now.addingTimeInterval(expiresIn)
        if let uid = obj["user_id"] as? String, !uid.isEmpty { c.remoteAccountID = uid }
        return c
    }

    public static func decode(_ data: Data, accountID: AccountID, now: Date) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let used = ClaudeProvider.number(root["character_count"]),
              let limit = ClaudeProvider.number(root["character_limit"]) else {
            throw ProviderError.schema(keys: root.keys.sorted())
        }
        let percent = limit > 0 ? ((used / limit * 100) * 10).rounded() / 10 : nil
        let meter = Meter(
            kind: .window,
            label: "Credits",
            percentUsed: percent,
            used: used,
            limit: limit,
            unit: "credits",
            resetsAt: ClaudeProvider.number(root["next_character_count_reset_unix"]).map { Date(timeIntervalSince1970: $0) },
            windowLength: .seconds(monthSeconds)
        )
        return UsageSnapshot(accountID: accountID, fetchedAt: now, plan: planName(root["tier"] as? String), meters: [meter])
    }

    /// `character_refresh_period` is monthly; a 30-day window renders the reset as a date.
    static let monthSeconds = 30 * 86400

    static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
