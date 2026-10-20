// S1 spike: Claude OAuth PKCE loopback probe. Throwaway. Tokens stay in memory only.
import CryptoKit
import Foundation
import Network
import Security

let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
let authorizeURL = "https://claude.com/cai/oauth/authorize"
let tokenURL = "https://platform.claude.com/v1/oauth/token"
let usageURL = "https://api.anthropic.com/api/oauth/usage"
let betaHeader = "oauth-2025-04-20"

func log(_ s: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] \(s)")
    fflush(stdout)
}

func fail(_ s: String) -> Never {
    log("ERROR: \(s)")
    exit(1)
}

// MARK: args
var scope = "user:profile"
var pollCount = 0
var loginHint: String?
var argv = Array(CommandLine.arguments.dropFirst())
func nextArg(_ flag: String) -> String {
    if argv.isEmpty { fail("\(flag) needs a value") }
    return argv.removeFirst()
}
while !argv.isEmpty {
    let a = argv.removeFirst()
    switch a {
    case "--scope": scope = nextArg(a)
    case "--poll": guard let n = Int(nextArg(a)), n > 0 else { fail("--poll needs a positive integer") }
        pollCount = n
    case "--login-hint": loginHint = nextArg(a)
    default: fail("unknown arg \(a). usage: S1Probe [--scope 'a b'] [--poll N] [--login-hint email]")
    }
}

// MARK: CC keychain item metadata (attributes only, never -w/-g)
func ccItemMetadata(_ label: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    do { try p.run() } catch { log("cc-item[\(label)]: cannot run security: \(error)"); return }
    p.waitUntilExit()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let keep = text.split(separator: "\n").filter { line in
        ["keychain:", "\"mdat\"", "\"cdat\"", "\"acct\"", "\"svce\"", "class:"].contains { line.contains($0) }
    }
    log("cc-item[\(label)] exit=\(p.terminationStatus)")
    keep.forEach { print("    \($0.trimmingCharacters(in: .whitespaces))") }
}

// MARK: PKCE
func randomBytes(_ n: Int) -> Data {
    var d = Data(count: n)
    let rc = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
    guard rc == errSecSuccess else { fail("SecRandomCopyBytes failed \(rc)") }
    return d
}

func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<x.count { diff |= x[i] ^ y[i] }
    return diff == 0
}

let verifier = b64url(randomBytes(32))
let challenge = b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
let state = b64url(randomBytes(32))

// MARK: loopback listener
enum Outcome { case code(String), failure(String) }
final class Box<T> { var value: T?; let sem = DispatchSemaphore(value: 0) }

let queue = DispatchQueue(label: "s1.listener")
let params = NWParameters.tcp
params.allowLocalEndpointReuse = false
params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
let listener: NWListener
do { listener = try NWListener(using: params) } catch { fail("NWListener create: \(error)") }

let ready = Box<UInt16>()
let result = Box<Outcome>()
var handled = false

listener.stateUpdateHandler = { st in
    switch st {
    case .ready: ready.value = listener.port?.rawValue; ready.sem.signal()
    case .failed(let e): log("listener failed: \(e)"); ready.sem.signal()
    default: break
    }
}

func respond(_ c: NWConnection, _ status: String, _ body: String) {
    let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n"
        + "Referrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
}

listener.newConnectionHandler = { conn in
    conn.start(queue: queue)
    conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
        guard let data, let req = String(data: data, encoding: .utf8) else { return respond(conn, "400 Bad Request", "bad") }
        let lines = req.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        let port = ready.value ?? 0
        let host = lines.first { $0.lowercased().hasPrefix("host:") }?.dropFirst(5).trimmingCharacters(in: .whitespaces) ?? ""
        guard !handled, parts.count == 3, parts[0] == "GET",
              host == "127.0.0.1:\(port)" || host == "localhost:\(port)",
              let comps = URLComponents(string: String(parts[1])), comps.path == "/callback"
        else { return respond(conn, "400 Bad Request", "bad request") }
        handled = true
        let q = Dictionary(comps.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { a, _ in a })
        respond(conn, "200 OK", "<html><body><p>You can close this tab.</p></body></html>")
        if let err = q["error"] {
            result.value = .failure("authorize error=\(err) description=\(q["error_description"] ?? "-")")
        } else if !constantTimeEqual(q["state"] ?? "", state) {
            result.value = .failure("state mismatch")
        } else if let code = q["code"], !code.isEmpty {
            result.value = .code(code)
        } else {
            result.value = .failure("callback without code; keys=\(q.keys.sorted())")
        }
        result.sem.signal()
    }
}

ccItemMetadata("before")
listener.start(queue: queue)
ready.sem.wait()
guard let port = ready.value, port != 0 else { fail("listener did not bind 127.0.0.1") }
let redirect = "http://127.0.0.1:\(port)/callback"
log("listening on \(redirect)")

var auth = URLComponents(string: authorizeURL)!
auth.queryItems = [
    .init(name: "code", value: "true"),
    .init(name: "client_id", value: clientID),
    .init(name: "response_type", value: "code"),
    .init(name: "redirect_uri", value: redirect),
    .init(name: "scope", value: scope),
    .init(name: "code_challenge", value: challenge),
    .init(name: "code_challenge_method", value: "S256"),
    .init(name: "state", value: state),
] + (loginHint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
// Note: the URL carries challenge + state only, never the verifier.
let authURL = auth.url!.absoluteString
log("scope=\(scope)")
print("\nOpen this URL (opening default browser now):\n\(authURL)\n")
log("If the page shows an error about redirect_uri, copy that exact text: the spike does not fall back.")
let opener = Process()
opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
opener.arguments = [authURL]
try? opener.run()

if result.sem.wait(timeout: .now() + 300) == .timedOut { listener.cancel(); fail("timeout after 5 min, no callback") }
listener.cancel()
let code: String
switch result.value! {
case .failure(let m): fail(m)
case .code(let c): code = c
}
log("callback received (code length \(code.count))")

// MARK: HTTP helper
func http(_ req: URLRequest) -> (Int, [AnyHashable: Any], Data) {
    let box = Box<(Int, [AnyHashable: Any], Data)>()
    URLSession.shared.dataTask(with: req) { d, r, e in
        if let e { log("transport error: \(e)") }
        let h = r as? HTTPURLResponse
        box.value = (h?.statusCode ?? -1, h?.allHeaderFields ?? [:], d ?? Data())
        box.sem.signal()
    }.resume()
    box.sem.wait()
    return box.value!
}

// MARK: token exchange (code may arrive as "code#state")
let rawCode = code.split(separator: "#").first.map(String.init) ?? code
var treq = URLRequest(url: URL(string: tokenURL)!)
treq.httpMethod = "POST"
treq.setValue("application/json", forHTTPHeaderField: "Content-Type")
treq.httpBody = try! JSONSerialization.data(withJSONObject: [
    "grant_type": "authorization_code",
    "code": rawCode,
    "redirect_uri": redirect,
    "client_id": clientID,
    "code_verifier": verifier,
    "state": state,
])
let (tstatus, _, tdata) = http(treq)
let tjson = (try? JSONSerialization.jsonObject(with: tdata)) as? [String: Any] ?? [:]
guard tstatus == 200, let accessToken = tjson["access_token"] as? String else {
    // Error bodies carry no token; print error/description fields only.
    fail("token exchange HTTP \(tstatus) error=\(tjson["error"] ?? "-") desc=\(tjson["error_description"] ?? String(decoding: tdata.prefix(500), as: UTF8.self))")
}
log("token exchange 200; response keys=\(tjson.keys.sorted()); granted scope=\(tjson["scope"] ?? "-"); expires_in=\(tjson["expires_in"] ?? "-"); has_refresh=\(tjson["refresh_token"] != nil)")

// MARK: usage
func usageRequest() -> URLRequest {
    var r = URLRequest(url: URL(string: usageURL)!)
    r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    r.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
    r.setValue("claude-usage-spike/0.1", forHTTPHeaderField: "User-Agent")
    return r
}

func shapeReport(_ data: Data) {
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { log("usage body not JSON"); return }
    print("  top-level keys: \(j.keys.sorted())")
    for (i, l) in ((j["limits"] as? [[String: Any]]) ?? []).enumerated() {
        let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] ?? "-"
        print("  limits[\(i)] kind=\(l["kind"] ?? "-") group=\(l["group"] ?? "-") percent=\(l["percent"] ?? "-") resets_at=\(l["resets_at"] ?? "-") model=\(model)")
    }
    if let s = j["spend"] as? [String: Any] {
        for k in s.keys.sorted() { print("  spend.\(k)=\(s[k]!)") }
    } else { print("  spend: absent/null") }
    if let e = j["extra_usage"] as? [String: Any] {
        print("  extra_usage currency=\(e["currency"] ?? "-") used_credits=\(e["used_credits"] ?? "-") monthly_limit=\(e["monthly_limit"] ?? "-")")
    }
}

let (ustatus, _, udata) = http(usageRequest())
log("usage HTTP \(ustatus)")
if ustatus == 200 { shapeReport(udata) } else { print("  body (first 300B): \(String(decoding: udata.prefix(300), as: UTF8.self))") }

for i in stride(from: 1, through: pollCount, by: 1) {
    Thread.sleep(forTimeInterval: 60)
    let (s, h, _) = http(usageRequest())
    log("poll \(i)/\(pollCount) HTTP \(s) Retry-After=\(h["Retry-After"] ?? h["retry-after"] ?? "-")")
}

ccItemMetadata("after")
log("done; tokens discarded with process")
