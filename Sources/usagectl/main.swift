import Foundation
import UsageCore
import UsageCoreMac

let service = "cc.kuoc.agent-hourglass.cli"
let store = CredentialStore(service: service)

struct AccountsFile: Codable { var accounts: [String] }

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func accountsURL() throws -> URL { try AppSupport.directory().appendingPathComponent("usagectl-accounts.json") }

func loadAccount() throws -> AccountID {
    guard let data = try? Data(contentsOf: accountsURL()),
          let f = try? JSONDecoder().decode(AccountsFile.self, from: data),
          let raw = f.accounts.first, let id = AccountID(rawValue: raw)
    else { die("no account: run `usagectl login` first") }
    return id
}

func makeClient(_ id: AccountID) -> AccountClient {
    AccountClient(id: id, provider: ClaudeProvider(), http: HTTPClient(), store: store, clock: ContinuousClock(), now: { Date() })
}

func argValue(_ args: [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func login(_ args: [String]) async throws {
    let (cred, remote) = try await ClaudePKCEFlow().run(loginHint: argValue(args, "--hint")) { url in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        print("Open this URL if the browser did not open:\n\(url.absoluteString)\n")
        p.arguments = [url.absoluteString]
        try? p.run()
    }
    let id = AccountID(kind: .claude, remoteID: remote)
    try store.write(cred, for: id, label: "Claude Usage CLI (\(id.rawValue))")
    try AppSupport.secureWrite(JSONEncoder().encode(AccountsFile(accounts: [id.rawValue])), to: accountsURL())
    print("login ok id=claude:\(remote.prefix(8))…")
}

func fetchOnce() async throws {
    let outcome = await makeClient(try loadAccount()).fetch()
    print(SoakLine.format(at: Date(), outcome: outcome, count429: 0))
    if case .failure = outcome { exit(2) }
}

func soak(_ args: [String]) async throws {
    let hours = Double(argValue(args, "--hours") ?? "") ?? 0
    let minutes = Double(argValue(args, "--minutes") ?? "") ?? (hours > 0 ? hours * 60 : 120)
    let interval = Int(argValue(args, "--interval") ?? "") ?? 60
    let dir = try AppSupport.directory()
    let lock: InstanceLock
    do { lock = try InstanceLock.acquire(at: dir.appendingPathComponent("usagectl.lock")) } catch {
        die("another usagectl soak is running")
    }
    let id = try loadAccount()
    let log = try SoakLogFile(url: dir.appendingPathComponent("soak.log"))
    print("soak: \(Int(minutes)) min, interval \(interval)s, log \(log.url.path)")
    let counter = Counter()
    let poller = Poller(clients: [makeClient(id)], clock: ContinuousClock(), now: { Date() }) { _, outcome in
        let n = await counter.record(outcome)
        let line = SoakLine.format(at: Date(), outcome: outcome, count429: n)
        log.append(line)
        print(line)
    }
    await poller.setUserInterval(.seconds(interval))
    await poller.setForeground(true)
    await poller.start()
    try await Task.sleep(for: .seconds(minutes * 60))
    await poller.stop()
    withExtendedLifetime(lock) {}
    print("soak done")
}

actor Counter {
    var n429 = 0
    func record(_ o: FetchOutcome) -> Int {
        if case .failure(.rateLimited) = o { n429 += 1 }
        return n429
    }
}

func logout() throws {
    let id = try loadAccount()
    try store.delete(id)
    try? FileManager.default.removeItem(at: accountsURL())
    print("logout ok")
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "login": try await login(args)
    case "fetch": try await fetchOnce()
    case "soak": try await soak(args)
    case "logout": try logout()
    default: die("usage: usagectl login [--hint email] | fetch | soak [--hours H | --minutes M] [--interval S] | logout")
    }
} catch {
    die("error: \(error)")
}
