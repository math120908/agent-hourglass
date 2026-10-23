import CryptoKit
import Foundation

/// CSPRNG bytes. SystemRandomNumberGenerator is backed by the kernel CSPRNG (arc4random_buf /
/// getentropy), equivalent to SecRandomCopyBytes, and keeps `import Security` out of this file.
public func secureRandom(_ count: Int) -> [UInt8] {
    var rng = SystemRandomNumberGenerator()
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
}

func base64url(_ bytes: some Sequence<UInt8>) -> String {
    Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// RFC 7636 PKCE pair (S256) plus an OAuth `state`.
public struct PKCE: Sendable {
    public let verifier: Secret
    public let challenge: String
    public let state: String

    public static func challenge(for verifier: String) -> String {
        base64url(SHA256.hash(data: Data(verifier.utf8)))
    }

    public static func make(random: (Int) -> [UInt8] = secureRandom) -> PKCE {
        let v = base64url(random(32))
        return PKCE(verifier: Secret(v), challenge: challenge(for: v), state: base64url(random(32)))
    }
}

/// Constant-time comparison of two strings' UTF-8 bytes.
public func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    // Length is not secret; an early exit avoids UInt8-folded length collisions.
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<x.count { diff |= x[i] ^ y[i] }
    return diff == 0
}
