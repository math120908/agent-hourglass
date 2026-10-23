import Foundation
import Security

public protocol CredentialStoring: Sendable {
    func read(_ id: AccountID) throws -> Credential?
    func write(_ c: Credential, for id: AccountID, label: String) throws
    func delete(_ id: AccountID) throws
    func allAccountIDs() throws -> [AccountID]
}

public enum CredentialStoreError: Error, Sendable, Equatable {
    case unexpected(status: Int32)
    case corrupt
}

/// The only Keychain gateway. Every query is scoped to `service` via `query(for:)`.
public struct CredentialStore: CredentialStoring {
    public static let service = "cc.kuoc.agent-hourglass"
    static let maxAccounts = 64

    public let service: String
    public let accessGroup: String?

    public init(service: String = CredentialStore.service, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Single query builder: always generic-password class + this service (+ access group if set).
    func query(for id: AccountID?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let id { q[kSecAttrAccount as String] = id.rawValue }
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    /// Query used by `read`. Internal so tests can inspect it without touching the Keychain.
    func readQuery(for id: AccountID) -> [String: Any] {
        var q = query(for: id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return q
    }

    /// Attributes `write` sets on both update and add (never synchronizable).
    func writeAttributes(data: Data, label: String) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    /// Dictionary passed to `SecItemAdd` when `write` creates a new item.
    func addQuery(for id: AccountID, data: Data, label: String) -> [String: Any] {
        query(for: id).merging(writeAttributes(data: data, label: label)) { _, new in new }
    }

    /// Query used by `allAccountIDs`.
    func listQuery() -> [String: Any] {
        var q = query(for: nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = Self.maxAccounts
        return q
    }

    public func read(_ id: AccountID) throws -> Credential? {
        let q = readQuery(for: id)
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.unexpected(status: status) }
        guard let data = out as? Data, let c = try? JSONDecoder().decode(Credential.self, from: data) else {
            throw CredentialStoreError.corrupt
        }
        return c
    }

    public func write(_ c: Credential, for id: AccountID, label: String) throws {
        let data = try JSONEncoder().encode(c)
        let attrs = writeAttributes(data: data, label: label)
        var status = SecItemUpdate(query(for: id) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(addQuery(for: id, data: data, label: label) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.unexpected(status: status) }
    }

    public func delete(_ id: AccountID) throws {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpected(status: status)
        }
    }

    public func allAccountIDs() throws -> [AccountID] {
        let q = listQuery()
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw CredentialStoreError.unexpected(status: status) }
        let items = (out as? [[String: Any]]) ?? ((out as? [String: Any]).map { [$0] } ?? [])
        return items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(AccountID.init(rawValue:)) }
    }
}

/// Test double; `writeError` makes `write` throw.
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AccountID: Credential] = [:]
    private var _writeError: (any Error)?

    public init() {}

    public var writeError: (any Error)? {
        get { lock.withLock { _writeError } }
        set { lock.withLock { _writeError = newValue } }
    }

    public func read(_ id: AccountID) throws -> Credential? { lock.withLock { items[id] } }

    public func write(_ c: Credential, for id: AccountID, label: String) throws {
        try lock.withLock {
            if let e = _writeError { throw e }
            items[id] = c
        }
    }

    public func delete(_ id: AccountID) throws { lock.withLock { _ = items.removeValue(forKey: id) } }

    public func allAccountIDs() throws -> [AccountID] { lock.withLock { Array(items.keys) } }
}
