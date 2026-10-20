import Foundation

public struct AccountEntry: Codable, Equatable, Sendable {
    public var id: AccountID
    public var kind: ProviderKind
    public var displayName: String
    public var remoteLogin: String?
    public var order: Int
    public var addedAt: Date
    public var status: String

    public init(id: AccountID, kind: ProviderKind, displayName: String, remoteLogin: String?, order: Int, addedAt: Date, status: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.remoteLogin = remoteLogin
        self.order = order
        self.addedAt = addedAt
        self.status = status
    }
}

public enum AccountRegistryError: Error, Equatable {
    case unknownAccount
    case emptyName
    case unsupportedVersion(Int)
}

/// Owns `accounts.json` (spec §4). Non-secret metadata only; every write goes through `AppSupport.secureWrite`.
public actor AccountRegistry {
    struct File: Codable {
        var version: Int
        var menuBarAccountID: AccountID?
        var accounts: [AccountEntry]
    }

    public static let fileName = "accounts.json"
    public nonisolated let url: URL
    private var entries: [AccountEntry] = []
    public private(set) var menuBarAccountID: AccountID?

    public init(directory: URL) {
        url = directory.appendingPathComponent(Self.fileName)
    }

    /// Reads the registry. A missing file is an empty list; an unreadable one is moved aside to
    /// `accounts.json.bad-<ts>` (0600) and the registry starts empty.
    public func load() throws -> [AccountEntry] {
        guard let data = try? Data(contentsOf: url) else {
            entries = []
            menuBarAccountID = nil
            return []
        }
        do {
            let file = try Self.decoder.decode(File.self, from: data)
            guard file.version == 1 else { throw AccountRegistryError.unsupportedVersion(file.version) }
            entries = file.accounts.sorted { $0.order < $1.order }
            menuBarAccountID = file.menuBarAccountID.flatMap { id in entries.contains { $0.id == id } ? id : nil }
                ?? entries.first?.id
        } catch {
            try quarantine()
            entries = []
            menuBarAccountID = nil
        }
        return entries
    }

    public func accounts() -> [AccountEntry] { entries }

    /// Inserts a new entry at the end, or replaces an existing one with the same id (re-auth), keeping its order.
    public func upsert(_ entry: AccountEntry) throws {
        var next = entries
        if let i = next.firstIndex(where: { $0.id == entry.id }) {
            var e = entry
            e.order = next[i].order
            next[i] = e
        } else {
            var e = entry
            e.order = (next.map(\.order).max() ?? -1) + 1
            next.append(e)
        }
        try commit(next, menuBar: menuBarAccountID ?? entry.id)
    }

    /// Removes the entry; if it was the menu bar account, the next in registry order is promoted.
    public func remove(_ id: AccountID) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { throw AccountRegistryError.unknownAccount }
        var next = entries
        next.remove(at: i)
        var menuBar = menuBarAccountID
        if menuBar == id { menuBar = next.isEmpty ? nil : next[min(i, next.count - 1)].id }
        try commit(next, menuBar: menuBar)
    }

    /// Rejects blank names so the previous name stays.
    public func rename(_ id: AccountID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountRegistryError.emptyName }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { throw AccountRegistryError.unknownAccount }
        var next = entries
        next[i].displayName = trimmed
        try commit(next, menuBar: menuBarAccountID)
    }

    /// Applies `ids` as the new order; ids not listed keep their relative order after the listed ones.
    public func reorder(_ ids: [AccountID]) throws {
        let listed = ids.compactMap { id in entries.first { $0.id == id } }
        let rest = entries.filter { !ids.contains($0.id) }
        let next = (listed + rest).enumerated().map { i, e in var e = e; e.order = i; return e }
        try commit(next, menuBar: menuBarAccountID)
    }

    public func setMenuBarAccount(_ id: AccountID) throws {
        guard entries.contains(where: { $0.id == id }) else { throw AccountRegistryError.unknownAccount }
        try commit(entries, menuBar: id)
    }

    private func commit(_ next: [AccountEntry], menuBar: AccountID?) throws {
        let data = try Self.encoder.encode(File(version: 1, menuBarAccountID: menuBar, accounts: next))
        try AppSupport.secureWrite(data, to: url)
        entries = next
        menuBarAccountID = menuBar
    }

    private func quarantine() throws {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let bad = url.deletingLastPathComponent().appendingPathComponent("\(Self.fileName).bad-\(ts)")
        guard Darwin.rename(url.path, bad.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard chmod(bad.path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
