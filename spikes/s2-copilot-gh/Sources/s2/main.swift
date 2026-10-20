// Throwaway spike S2: gh token -> copilot_internal/user shape probe. Never prints tokens.
import Foundation

let ghPath = "/opt/homebrew/bin/gh"

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }

func checkBinary() {
    let resolved = URL(fileURLWithPath: ghPath).resolvingSymlinksInPath().path
    guard let a = try? FileManager.default.attributesOfItem(atPath: resolved) else { fail("gh missing") }
    let owner = (a[.ownerAccountID] as? NSNumber)?.uint32Value ?? .max
    let perms = (a[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
    guard owner == 0 || owner == getuid() else { fail("gh owner not root/current user") }
    guard perms & 0o022 == 0 else { fail("gh is group/world-writable") }
    print("gh ok: \(resolved) owner=\(owner) mode=\(String(perms, radix: 8))")
}

/// Runs gh with fixed args; stdout into memory, stderr discarded, empty env apart from HOME/USER. Returns nil on timeout/failure.
func runGH(_ args: [String], timeout: TimeInterval = 5) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ghPath)
    p.arguments = args
    let env = ProcessInfo.processInfo.environment
    p.environment = ["HOME": env["HOME"] ?? "", "USER": env["USER"] ?? "", "PATH": "/usr/bin:/bin"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    var data = Data()
    let readDone = DispatchSemaphore(value: 0)
    do { try p.run() } catch { return nil }
    DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); readDone.signal() }
    let exited = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { p.waitUntilExit(); exited.signal() }
    if exited.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
    readDone.wait()
    return p.terminationStatus == 0 ? data : nil
}

func logins() -> [String] {
    // gh auth status prints to stdout in gh 2.x; parse "account <login>" lines under github.com.
    guard let d = runGH(["auth", "status", "--hostname", "github.com"]), let s = String(data: d, encoding: .utf8) else { return [] }
    return s.split(separator: "\n").compactMap { line in
        guard let r = line.range(of: "account ") else { return nil }
        return line[r.upperBound...].split(separator: " ").first.map(String.init)
    }
}

func token(_ login: String) -> String? {
    guard let d = runGH(["auth", "token", "--user", login]) else { return nil }
    let t = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return t.isEmpty ? nil : t
}

func probe(_ login: String) {
    guard let tok = token(login) else { print("[\(login)] token: FAIL"); return }
    var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
    req.setValue("token \(tok)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("[\(login)] HTTP \(code)\(err.map { " err=\($0.localizedDescription)" } ?? "")")
        guard code == 200, let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        print("  copilot_plan=\(j["copilot_plan"] ?? "nil") quota_reset_date=\(j["quota_reset_date"] ?? "nil")")
        for (k, v) in (j["quota_snapshots"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let q = v as? [String: Any] ?? [:]
            print("  \(k): entitlement=\(q["entitlement"] ?? "nil") remaining=\(q["remaining"] ?? "nil") percent_remaining=\(q["percent_remaining"] ?? "nil")")
        }
    }.resume()
    sem.wait()
}

func latency(_ login: String, _ n: Int) {
    var ms: [Double] = []
    var fails = 0
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        if token(login) == nil { fails += 1 }
        ms.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    ms.sort()
    func pct(_ p: Double) -> Double { ms[min(ms.count - 1, Int((p * Double(ms.count)).rounded(.up)) - 1)] }
    print(String(format: "[%@] latency n=%d fails=%d p50=%.1fms p95=%.1fms max=%.1fms", login, n, fails, pct(0.5), pct(0.95), ms.last!))
}

checkBinary()
let ls = logins()
print("logins: \(ls)")
let a = CommandLine.arguments
if let i = a.firstIndex(of: "--latency") {
    let n = i + 1 < a.count ? Int(a[i + 1]) ?? 50 : 50
    ls.forEach { latency($0, n) }
} else {
    ls.forEach(probe)
}
