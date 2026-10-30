import Foundation
import os

/// Grok (xAI) RFC 8628 device-code login against `auth.x.ai`: start, poll the token endpoint,
/// then refresh the rotating token chain.
public struct GrokDeviceAuth: Sendable {
    public static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    public static let issuer = URL(string: "https://auth.x.ai")!
    static let deviceURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    static let userinfoURL = URL(string: "https://auth.x.ai/oauth2/userinfo")!
    /// Exactly the Grok-CLI client's scope (R10 §3); never widened with guesses such as `billing:read`.
    public static let scope = "openid profile email offline_access grok-cli:access api:access"
    /// Used when the server's verification URL is not https or not on an xAI host.
    static let fallbackVerificationURL = URL(string: "https://x.ai/device")!
    static let verificationHosts: Set<String> = ["x.ai", "accounts.x.ai", "auth.x.ai"]
    static let minInterval: Duration = .seconds(5)
    static let slowDownStep: Duration = .seconds(5)
    static let maxLifetime: TimeInterval = 15 * 60

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "GrokDeviceAuth")

    private let http: HTTPClient
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    /// Measures the poll interval on a clock that keeps counting through device sleep.
    private let monotonic: @Sendable () -> ContinuousClock.Instant

    public init(
        http: HTTPClient,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        monotonic: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.http = http
        self.sleep = sleep
        self.now = now
        self.monotonic = monotonic
    }

    public func start() async throws -> DeviceCodePrompt {
        let (data, status) = try await post(Self.deviceURL, form: ["client_id": Self.clientID, "scope": Self.scope], step: "start")
        guard (200..<300).contains(status) else {
            Self.log.error("device login start failed: HTTP \(status, privacy: .public)")
            throw DeviceFlowError.unexpected(status: status)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let device = obj["device_code"] as? String, !device.isEmpty,
              let code = obj["user_code"] as? String, !code.isEmpty else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        let lifetime = CodexDeviceAuth.number(obj["expires_in"]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Self.maxLifetime
        return DeviceCodePrompt(
            userCode: code,
            verificationURL: Self.verificationURL(obj["verification_uri_complete"] ?? obj["verification_uri"]),
            interval: CodexDeviceAuth.interval(obj["interval"]),
            expiresAt: now().addingTimeInterval(min(lifetime, Self.maxLifetime)),
            deviceCode: Secret(device)
        )
    }

    /// `wake` (foreground return) polls at once when the interval has already elapsed.
    public func poll(_ p: DeviceCodePrompt, wake: DevicePollWake? = nil) async throws -> Credential {
        let deadline = min(p.expiresAt, now().addingTimeInterval(Self.maxLifetime))
        var interval = max(p.interval, Self.minInterval)
        let form = [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": p.deviceCode.reveal(),
            "client_id": Self.clientID,
        ]
        while true {
            try Task.checkCancellation()
            guard now() < deadline else {
                Self.log.info("device login expired")
                throw DeviceFlowError.expired
            }
            let polledAt = monotonic()
            var tokens: Credential?
            do {
                let (data, status) = try await post(Self.tokenURL, form: form, step: "poll")
                // A restart cancelled this login while the POST was in flight: drop its answer.
                try Task.checkCancellation()
                switch status {
                case 200..<300:
                    tokens = try Self.credential(fromTokenResponse: data, now: now())
                case 400:
                    switch CodexDeviceAuth.errorCode(data) {
                    case "authorization_pending":
                        break
                    case "slow_down":
                        interval += Self.slowDownStep
                        Self.log.info("device login slow_down")
                    case "access_denied":
                        Self.log.info("device login denied")
                        throw DeviceFlowError.denied
                    case "expired_token":
                        Self.log.info("device login expired")
                        throw DeviceFlowError.expired
                    default:
                        Self.log.error("device login poll failed: HTTP 400")
                        throw DeviceFlowError.unexpected(status: 400)
                    }
                default:
                    Self.log.error("device login poll failed: HTTP \(status, privacy: .public)")
                    throw DeviceFlowError.unexpected(status: status)
                }
            } catch ProviderError.transport {
                // Suspension in Safari drops the connection (-999 / -1005); retry on the next interval.
                Self.log.info("device login poll: transport error, retrying")
            } catch ProviderError.rateLimited {
                interval += Self.slowDownStep
                Self.log.info("device login poll: HTTP 429, slowing down")
            } catch let ProviderError.http(status, _, _) {
                Self.log.error("device login poll failed: HTTP \(status, privacy: .public)")
                throw DeviceFlowError.unexpected(status: status)
            }
            // Outside the retrying catch: the device code is spent, so a userinfo failure ends the login.
            if let tokens { return try await identity(for: tokens) }
            try await CodexDeviceAuth.pause(interval, since: polledAt, wake: wake, sleep: sleep, monotonic: monotonic)
        }
    }

    /// Fills `sub` and `email` from `userinfo` when the token response carried no id_token.
    func identity(for c: Credential) async throws -> Credential {
        guard c.remoteAccountID == nil else { return c }
        var req = URLRequest(url: Self.userinfoURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            (data, _) = try await http.send(req, bearer: c.access)
        } catch let error as ProviderError {
            Self.log.error("userinfo failed: \(error.description, privacy: .public)")
            throw error
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let sub = Self.nonEmpty(obj?["sub"]) else {
            Self.log.error("userinfo: no sub")
            throw ProviderError.schema(keys: ["sub"])
        }
        var out = c
        out.remoteAccountID = sub
        out.accountEmail = Self.nonEmpty(obj?["email"]) ?? c.accountEmail
        return out
    }

    /// Rotates the refresh token (R10 §3: a spent one gets 400 `invalid_grant`). Single use: never retried.
    public func refresh(_ c: Credential) async throws -> Credential {
        guard let rt = c.refresh?.reveal(), !rt.isEmpty else {
            Self.log.error("refresh: invalidGrant (no refresh token)")
            throw ProviderError.invalidGrant
        }
        var req = Self.formRequest(Self.tokenURL, form: ["grant_type": "refresh_token", "refresh_token": rt, "client_id": Self.clientID])
        req.timeoutInterval = CodexDeviceAuth.refreshTimeout
        let data: Data
        do {
            (data, _) = try await http.send(req, bearer: nil)
        } catch ProviderError.unauthorized {
            Self.log.error("refresh: HTTP 401 invalidGrant")
            throw ProviderError.invalidGrant
        } catch let ProviderError.http(status, _, _) where status == 400 {
            Self.log.error("refresh: HTTP 400 invalidGrant")
            throw ProviderError.invalidGrant
        } catch let error as ProviderError {
            Self.log.error("refresh failed: \(error.description, privacy: .public)")
            throw error
        }
        return try Self.credential(fromTokenResponse: data, now: now(), previous: c)
    }

    /// `previous` set means a refresh: refresh_token and identity fall back to it.
    /// The id_token is read for `sub` / `email` only (TLS straight from the issuer) and not kept.
    static func credential(fromTokenResponse data: Data, now: Date, previous: Credential? = nil) throws -> Credential {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let access = obj["access_token"] as? String, !access.isEmpty else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        let refresh = (obj["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : Secret($0) } ?? previous?.refresh
        let expiresAt: Date?
        if let secs = CodexDeviceAuth.number(obj["expires_in"]) {
            expiresAt = now.addingTimeInterval(secs)
        } else if let exp = CodexDeviceAuth.number(CodexDeviceAuth.jwtPayload(access)?["exp"]) {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else {
            expiresAt = nil
        }
        let id = (obj["id_token"] as? String).flatMap(CodexDeviceAuth.jwtPayload)
        return Credential(
            kind: .grok,
            access: Secret(access),
            refresh: refresh,
            expiresAt: expiresAt,
            refreshExpiresAt: nil,
            scopes: [],
            remoteAccountID: nonEmpty(id?["sub"]) ?? previous?.remoteAccountID,
            accountEmail: nonEmpty(id?["email"]) ?? previous?.accountEmail
        )
    }

    static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        return s
    }

    /// The server's URL only when it is https on an xAI host; anything else gets the fixed fallback.
    static func verificationURL(_ raw: Any?) -> URL {
        guard let s = raw as? String, let url = URL(string: s),
              url.scheme == "https", verificationHosts.contains(url.host() ?? "") else {
            return fallbackVerificationURL
        }
        return url
    }

    /// Returns 2xx/400/401 bodies with their status; other statuses throw from `sendOAuth`.
    private func post(_ url: URL, form: [String: String], step: StaticString) async throws -> (Data, Int) {
        do {
            let (data, response) = try await http.sendOAuth(Self.formRequest(url, form: form))
            return (data, response.statusCode)
        } catch let error as ProviderError {
            if case .http = error {} else { Self.log.error("device login \(step, privacy: .public) failed: \(error.description, privacy: .public)") }
            throw error
        }
    }

    static func formRequest(_ url: URL, form: [String: String]) -> URLRequest {
        var c = URLComponents()
        c.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return req
    }
}
