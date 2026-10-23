import Foundation
import UsageCore

/// Widget-to-app links: `agenthourglass://account?id=<percent-encoded AccountID>`.
enum DeepLink {
    static let scheme = "agenthourglass"
    static let accountHost = "account"

    /// Only RFC 3986 unreserved characters pass unescaped, so `&`, `=`, `+`, `#` and `/` in an ID survive.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func url(for id: AccountID) -> URL {
        let encoded = id.rawValue.addingPercentEncoding(withAllowedCharacters: unreserved)!
        return URL(string: "\(scheme)://\(accountHost)?id=\(encoded)")!
    }

    static func accountID(from url: URL) -> AccountID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == accountHost,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              !value.isEmpty
        else { return nil }
        return AccountID(rawValue: value)
    }
}
