import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Refuses every redirect on a request that carries an Authorization header.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let authed = task.originalRequest?.value(forHTTPHeaderField: "Authorization") != nil
        completionHandler(authed ? nil : request)
    }
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public final class HTTPClient: Sendable {
    /// Hosts that may receive a bearer token. Any other host is rejected before sending.
    public static let authHosts: Set<String> = ["api.anthropic.com", "platform.claude.com", "claude.ai", "api.github.com"]

    let configuration: URLSessionConfiguration
    private let transport: HTTPTransport

    public init(transport: HTTPTransport? = nil, extraProtocolClasses: [AnyClass] = []) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if !extraProtocolClasses.isEmpty {
            config.protocolClasses = extraProtocolClasses + (config.protocolClasses ?? [])
        }
        configuration = config
        self.transport = transport ?? URLSessionTransport(
            session: URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
        )
    }

    public func send(_ req: URLRequest, bearer: Secret?) async throws -> (Data, HTTPURLResponse) {
        let host = req.url?.host() ?? ""
        var request = req
        if let bearer {
            guard Self.authHosts.contains(host), req.url?.scheme == "https" else {
                throw ProviderError.hostNotAllowed(host)
            }
            request.setValue("Bearer \(bearer.reveal())", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.transport(host: host)
        }

        let status = response.statusCode
        let retryAfter = Self.retryAfter(response)
        switch status {
        case 200..<300: return (data, response)
        case 300..<400 where bearer != nil: throw ProviderError.redirectRefused(host: host)
        case 401: throw ProviderError.unauthorized
        case 429: throw ProviderError.rateLimited(retryAfter: retryAfter)
        default: throw ProviderError.http(status: status, host: host, retryAfter: retryAfter)
        }
    }

    static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = Int(raw), seconds >= 0 { return .seconds(seconds) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = fmt.date(from: raw) else { return nil }
        return .seconds(max(0, Int(date.timeIntervalSinceNow.rounded(.up))))
    }
}
