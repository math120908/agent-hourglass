import Foundation

public struct AccountEntry: Codable, Equatable, Sendable {
    public var id: AccountID
    public var kind: ProviderKind
    public var displayName: String
    public var remoteLogin: String?
    public var order: Int
    public var addedAt: Date
    public var status: String
    /// True once the user renamed the account; an auto-derived name never overwrites it.
    public var nameIsCustom: Bool

    public init(
        id: AccountID,
        kind: ProviderKind,
        displayName: String,
        remoteLogin: String?,
        order: Int,
        addedAt: Date,
        status: String,
        nameIsCustom: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.remoteLogin = remoteLogin
        self.order = order
        self.addedAt = addedAt
        self.status = status
        self.nameIsCustom = nameIsCustom
    }

    /// Registries written before `nameIsCustom` existed decode it as false.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(AccountID.self, forKey: .id)
        kind = try c.decode(ProviderKind.self, forKey: .kind)
        displayName = try c.decode(String.self, forKey: .displayName)
        remoteLogin = try c.decodeIfPresent(String.self, forKey: .remoteLogin)
        order = try c.decode(Int.self, forKey: .order)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        status = try c.decode(String.self, forKey: .status)
        nameIsCustom = try c.decodeIfPresent(Bool.self, forKey: .nameIsCustom) ?? false
    }

    /// The name to store: a user rename always wins; otherwise `auto` (when known), else the old name, else `fallback`.
    public static func resolvedName(existing: AccountEntry?, auto: String?, fallback: String) -> String {
        if let existing, existing.nameIsCustom { return existing.displayName }
        return auto ?? existing?.displayName ?? fallback
    }
}

public enum AccountRegistryError: Error, Equatable {
    case unknownAccount
    case emptyName
    case unsupportedVersion(Int)
}

/// Owns `accounts.json` and `accounts-ext.json` (spec §4). Non-secret metadata only; every write goes through
/// `AppSupport.secureWrite`. Shipped builds (≤ v1.0.20) quarantine `accounts.json` on any kind they cannot decode
/// and then delete every Claude Keychain item, so kinds outside `storesInMainRegistry` live only in the ext file.
public actor AccountRegistry {
    struct File: Codable {
        var version: Int
        var menuBarAccountID: AccountID?
        var accounts: [AccountEntry]
    }

    private struct Header: Decodable {
        var version: Int
        var menuBarAccountID: AccountID?
    }

    /// One file's last loaded or written state; `raw` holds entries this build cannot decode, written back verbatim.
    private struct Slice {
        var entries: [AccountEntry] = []
        var raw: [Data] = []
    }

    public static let fileName = "accounts.json"
    public static let extFileName = "accounts-ext.json"
    public nonisolated let url: URL
    public nonisolated let extURL: URL
    private let isMain: @Sendable (ProviderKind) -> Bool
    private var entries: [AccountEntry] = []
    private var main = Slice()
    private var ext = Slice()
    private var mainMenuBar: AccountID?
    public private(set) var menuBarAccountID: AccountID?
    /// False when the last `load()` quarantined a file or threw; orphan cleanup must not trust `accounts()` then.
    public private(set) var loadedCleanly: Bool = true

    public init(directory: URL, isMain: @escaping @Sendable (ProviderKind) -> Bool = { $0.storesInMainRegistry }) {
        url = directory.appendingPathComponent(Self.fileName)
        extURL = directory.appendingPathComponent(Self.extFileName)
        self.isMain = isMain
    }

    /// Reads both files and merges them by `order` (main first on ties). A missing file is empty; an unparseable
    /// one (or `version != 1`) is moved aside to `<name>.bad-<ts>` (0600) and only that file starts empty.
    /// A single entry that fails to decode is hidden and kept verbatim.
    public func load() throws -> [AccountEntry] {
        loadedCleanly = true
        let (m, menuBar) = try read(url, name: Self.fileName)
        let (e, _) = try read(extURL, name: Self.extFileName)
        main = m
        ext = e
        mainMenuBar = menuBar
        entries = (m.entries + e.entries).enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
        menuBarAccountID = menuBar.flatMap { id in entries.contains { $0.id == id } ? id : nil } ?? entries.first?.id
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
        next[i].nameIsCustom = true
        try commit(next, menuBar: menuBarAccountID)
    }

    /// Applies `ids` as the new order; ids not listed keep their relative order after the listed ones.
    public func reorder(_ ids: [AccountID]) throws {
        let listed = ids.compactMap { id in entries.first { $0.id == id } }
        let rest = entries.filter { !ids.contains($0.id) }
        let next = (listed + rest).enumerated().map { i, e in var e = e; e.order = i; return e }
        try commit(next, menuBar: menuBarAccountID)
    }

    /// Persists the `Diagnostics.statusName` spelling the widget reads; a no-op when unchanged.
    public func setStatus(_ id: AccountID, _ status: String) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { throw AccountRegistryError.unknownAccount }
        guard entries[i].status != status else { return }
        var next = entries
        next[i].status = status
        try commit(next, menuBar: menuBarAccountID)
    }

    public func setMenuBarAccount(_ id: AccountID) throws {
        guard entries.contains(where: { $0.id == id }) else { throw AccountRegistryError.unknownAccount }
        try commit(entries, menuBar: id)
    }

    /// Partitions by `isMain` and rewrites only the file whose slice changed; `menuBarAccountID` goes to the main file only.
    private func commit(_ next: [AccountEntry], menuBar: AccountID?) throws {
        let nextMain = next.filter { isMain($0.kind) }
        let nextExt = next.filter { !isMain($0.kind) }
        if nextMain != main.entries || menuBar != mainMenuBar {
            try write(nextMain, raw: main.raw, menuBar: menuBar, to: url)
            main.entries = nextMain
            mainMenuBar = menuBar
        }
        if nextExt != ext.entries {
            try write(nextExt, raw: ext.raw, menuBar: nil, to: extURL)
            ext.entries = nextExt
        }
        entries = next
        menuBarAccountID = menuBar
    }

    private func write(_ accounts: [AccountEntry], raw: [Data], menuBar: AccountID?, to file: URL) throws {
        var data = try Self.encoder.encode(File(version: 1, menuBarAccountID: menuBar, accounts: accounts))
        if !raw.isEmpty {
            var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let kept = try raw.map { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
            object["accounts"] = (object["accounts"] as! [Any]) + kept
            data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        }
        try AppSupport.secureWrite(data, to: file)
    }

    /// Parses one file per entry. Returns an empty slice for a missing file and after quarantining a bad one.
    private func read(_ file: URL, name: String) throws -> (Slice, AccountID?) {
        guard let data = try? Data(contentsOf: file) else { return (Slice(), nil) }
        guard let header = try? Self.decoder.decode(Header.self, from: data),
              header.version == 1,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = object["accounts"] as? [Any]
        else {
            loadedCleanly = false
            try quarantine(file, name: name)
            return (Slice(), nil)
        }
        var slice = Slice()
        for element in accounts {
            guard let item = try? JSONSerialization.data(withJSONObject: element, options: .fragmentsAllowed) else { continue }
            if let entry = try? Self.decoder.decode(AccountEntry.self, from: item) {
                slice.entries.append(entry)
            } else {
                slice.raw.append(item)
            }
        }
        return (slice, header.menuBarAccountID)
    }

    private func quarantine(_ file: URL, name: String) throws {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let bad = file.deletingLastPathComponent().appendingPathComponent("\(name).bad-\(ts)")
        guard Darwin.rename(file.path, bad.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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
