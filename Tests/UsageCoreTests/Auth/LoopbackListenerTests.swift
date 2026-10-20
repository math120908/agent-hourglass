import Foundation
import Testing
@testable import UsageCore

/// Raw HTTP client so we control Host header and address family.
func rawRequest(_ host: String, _ port: UInt16, _ text: String) -> String? {
    var hints = addrinfo(ai_flags: AI_NUMERICHOST, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &res) == 0, let ai = res else { return nil }
    defer { freeaddrinfo(res) }
    let fd = socket(ai.pointee.ai_family, SOCK_STREAM, 0)
    defer { close(fd) }
    var tv = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    guard connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 else { return nil }
    _ = text.withCString { send(fd, $0, strlen($0), 0) }
    var out = [UInt8](), buf = [UInt8](repeating: 0, count: 4096)
    while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; out += buf[0..<n] }
    return String(decoding: out, as: UTF8.self)
}

func get(_ addr: String, _ port: UInt16, path: String, host: String? = nil) -> String? {
    rawRequest(addr, port, "GET \(path) HTTP/1.1\r\nHost: \(host ?? "localhost:\(port)")\r\nConnection: close\r\n\r\n")
}

func status(_ r: String?) -> String? { r?.split(separator: "\r\n").first.map(String.init) }

@Suite(.serialized) struct LoopbackListenerTests {
    func callback(_ l: LoopbackListener, state: String = "S", timeout: Duration = .seconds(5)) -> Task<String, Error> {
        Task { try await l.awaitCallback(expectedState: state, timeout: timeout) }
    }

    @Test func dualBindVisibleInLsof() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-a", "-p", "\(getpid())", "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        print("lsof dual-bind evidence:\n\(out)")
        #expect(out.contains("127.0.0.1:\(port)"))
        #expect(out.contains("[::1]:\(port)"))
        await l.close()
    }

    @Test(arguments: ["127.0.0.1", "::1"])
    func validCallbackReturnsCode(addr: String) async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let t = callback(l)
        let hostHdr = addr == "::1" ? "[::1]:\(port)" : "\(addr):\(port)"
        let r = get(addr, port, path: "/callback?code=abc%23S&state=S", host: hostHdr)
        #expect(status(r) == "HTTP/1.1 200 OK")
        #expect(try await t.value == "abc")
        #expect(!(r ?? "").contains("abc"))
    }

    @Test func urlSessionLocalhostWorks() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let t = callback(l)
        let (_, resp) = try await URLSession(configuration: .ephemeral).data(from: URL(string: "http://localhost:\(port)/callback?code=c1&state=S")!)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(try await t.value == "c1")
    }

    @Test func responseHasNoStoreHeaders() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let t = callback(l)
        let r = get("127.0.0.1", port, path: "/callback?code=c&state=S") ?? ""
        #expect(r.contains("Cache-Control: no-store"))
        #expect(r.contains("Referrer-Policy: no-referrer"))
        _ = try await t.value
    }

    @Test func stateMismatchRejected() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let t = callback(l)
        _ = get("127.0.0.1", port, path: "/callback?code=c&state=WRONG")
        await #expect(throws: AuthError.stateMismatch) { try await t.value }
    }

    @Test func wrongPath400() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        #expect(status(get("::1", port, path: "/other?code=c&state=S")) == "HTTP/1.1 400 Bad Request")
        await l.close()
    }

    @Test func foreignHost400() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        #expect(status(get("127.0.0.1", port, path: "/callback?code=c&state=S", host: "evil.com")) == "HTTP/1.1 400 Bad Request")
        #expect(status(get("127.0.0.1", port, path: "/callback?code=c&state=S", host: "localhost:1")) == "HTTP/1.1 400 Bad Request")
        await l.close()
    }

    @Test func postBody400() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let r = rawRequest("127.0.0.1", port, "POST /callback?code=c&state=S HTTP/1.1\r\nHost: localhost:\(port)\r\nContent-Length: 3\r\n\r\nabc")
        #expect(status(r) == "HTTP/1.1 400 Bad Request")
        let r2 = rawRequest("127.0.0.1", port, "GET /callback?code=c&state=S HTTP/1.1\r\nHost: localhost:\(port)\r\nContent-Length: 3\r\n\r\nabc")
        #expect(status(r2) == "HTTP/1.1 400 Bad Request")
        await l.close()
    }

    @Test func secondRequestRefused() async throws {
        let l = try await LoopbackListener.bind()
        let port = l.port
        let t = callback(l)
        _ = get("127.0.0.1", port, path: "/callback?code=c&state=S")
        _ = try await t.value
        let r = get("127.0.0.1", port, path: "/callback?code=c&state=S")
        #expect(r == nil || status(r) == "HTTP/1.1 400 Bad Request")
        let r6 = get("::1", port, path: "/callback?code=c&state=S", host: "[::1]:\(port)")
        #expect(r6 == nil || status(r6) == "HTTP/1.1 400 Bad Request")
    }

    @Test func timeoutThrows() async throws {
        let l = try await LoopbackListener.bind()
        await #expect(throws: AuthError.timeout) {
            try await l.awaitCallback(expectedState: "S", timeout: .milliseconds(200))
        }
    }

    @Test func ipv6BindFailureAborts() async throws {
        let attempts = Counter()
        await #expect(throws: AuthError.portUnavailable) {
            _ = try await LoopbackListener.bind(maxAttempts: 5, portPicker: { 0 }, binder: { family, port in
                if family == AF_INET6 { attempts.bump(); throw AuthError.portUnavailable }
                return try LoopbackListener.bindSocket(family: family, port: port)
            })
        }
        #expect(attempts.value == 5)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
