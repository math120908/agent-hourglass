import Foundation
import os

/// Codex (ChatGPT) device-code login: start, poll, then exchange the authorization code.
public struct CodexDeviceAuth: Sendable {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let issuer = URL(string: "https://auth.openai.com")!
    /// Fixed; never taken from a server response.
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    static let redirectURI = "https://auth.openai.com/deviceauth/callback"
    /// The only hosts this flow may talk to.
    static let allowedHosts: Set<String> = ["auth.openai.com"]
    static let minInterval: Duration = .seconds(5)
    static let slowDownStep: Duration = .seconds(5)
    static let maxLifetime: TimeInterval = 15 * 60

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "CodexDeviceAuth")

    private let http: HTTPClient
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        http: HTTPClient,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.sleep = sleep
        self.now = now
    }

    public func start() async throws -> DeviceCodePrompt {
        let data = try await post("api/accounts/deviceauth/usercode", json: ["client_id": Self.clientID], step: "start")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let id = obj["device_auth_id"] as? String,
              let code = (obj["user_code"] as? String) ?? (obj["usercode"] as? String) else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        return DeviceCodePrompt(
            userCode: code,
            verificationURL: Self.verificationURL,
            interval: Self.interval(obj["interval"]),
            expiresAt: now().addingTimeInterval(Self.maxLifetime),
            deviceCode: Secret(id)
        )
    }

    public func poll(_ p: DeviceCodePrompt) async throws -> Credential {
        let deadline = min(p.expiresAt, now().addingTimeInterval(Self.maxLifetime))
        var interval = max(p.interval, Self.minInterval)
        let body = ["device_auth_id": p.deviceCode.reveal(), "user_code": p.userCode]
        while true {
            try Task.checkCancellation()
            guard now() < deadline else {
                Self.log.info("device login expired")
                throw DeviceFlowError.expired
            }
            do {
                let data = try await post("api/accounts/deviceauth/token", json: body, step: "poll")
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ProviderError.schema(keys: [])
                }
                guard let code = obj["authorization_code"] as? String,
                      let verifier = obj["code_verifier"] as? String else {
                    throw ProviderError.schema(keys: obj.keys.sorted())
                }
                return try await exchange(code: code, verifier: verifier)
            } catch let ProviderError.http(status, _, _) where status == 403 || status == 404 {
                // pending
            } catch ProviderError.rateLimited {
                interval += Self.slowDownStep
                Self.log.info("device login slow_down")
            } catch let ProviderError.http(status, _, _) {
                Self.log.error("device login poll failed: HTTP \(status, privacy: .public)")
                throw DeviceFlowError.unexpected(status: status)
            } catch ProviderError.unauthorized {
                throw DeviceFlowError.unexpected(status: 401)
            }
            try await sleep(interval)
        }
    }

    private func exchange(code: String, verifier: String) async throws -> Credential {
        var c = URLComponents()
        c.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        let form = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        let data: Data
        do {
            data = try await send(path: "oauth/token", body: Data(form.utf8), contentType: "application/x-www-form-urlencoded")
        } catch let ProviderError.http(status, _, _) {
            Self.log.error("device login exchange failed: HTTP \(status, privacy: .public)")
            throw DeviceFlowError.unexpected(status: status)
        }
        return try Self.credential(fromTokenResponse: data, now: now())
    }

    static func credential(fromTokenResponse data: Data, now: Date) throws -> Credential {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let access = obj["access_token"] as? String,
              let idToken = obj["id_token"] as? String else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        guard let account = accountID(fromIDToken: idToken) else {
            throw ProviderError.schema(keys: ["chatgpt_account_id"])
        }
        let expiresAt: Date?
        if let secs = number(obj["expires_in"]) {
            expiresAt = now.addingTimeInterval(secs)
        } else if let exp = number(jwtPayload(access)?["exp"]) {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else {
            expiresAt = nil
        }
        return Credential(
            kind: .codex,
            access: Secret(access),
            refresh: (obj["refresh_token"] as? String).map(Secret.init),
            expiresAt: expiresAt,
            refreshExpiresAt: nil,
            scopes: [],
            remoteAccountID: account
        )
    }

    /// Reads only `["https://api.openai.com/auth"]["chatgpt_account_id"]`. No signature check:
    /// the token arrived over TLS straight from the issuer. The id_token is not kept.
    static func accountID(fromIDToken token: String) -> String? {
        let auth = jwtPayload(token)?["https://api.openai.com/auth"] as? [String: Any]
        guard let id = auth?["chatgpt_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func interval(_ raw: Any?) -> Duration {
        let secs = number(raw) ?? 0
        guard secs.isFinite, secs > 0, secs < 3600 else { return minInterval }
        return max(.seconds(secs), minInterval)
    }

    private static func number(_ raw: Any?) -> Double? {
        switch raw {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    private func post(_ path: String, json: [String: String], step: StaticString) async throws -> Data {
        do {
            return try await send(path: path, body: try JSONSerialization.data(withJSONObject: json), contentType: "application/json")
        } catch let error as ProviderError {
            if case .http = error {} else { Self.log.error("device login \(step) failed: \(error.description, privacy: .public)") }
            throw error
        }
    }

    private func send(path: String, body: Data, contentType: String) async throws -> Data {
        let url = Self.issuer.appending(path: path)
        guard url.scheme == "https", Self.allowedHosts.contains(url.host() ?? "") else {
            throw ProviderError.hostNotAllowed(url.host() ?? "")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body
        return try await http.send(req, bearer: nil).0
    }
}
