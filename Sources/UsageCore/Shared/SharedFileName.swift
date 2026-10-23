import CryptoKit
import Foundation

/// File-name stem for per-account files in the shared App Group directory.
/// Lowercase SHA-256 hex of the id's UTF-8 bytes: fixed length, injective in practice, and never
/// contains `/`, `..`, a leading `.`, or any part of the raw account id.
enum SharedFileName {
    static func forAccount(_ id: AccountID) -> String {
        SHA256.hash(data: Data(id.rawValue.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
