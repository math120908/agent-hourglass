import UsageCore
import Darwin
import Foundation

/// One-shot OAuth redirect listener bound to 127.0.0.1 and ::1 (IPV6_V6ONLY) on the same port.
/// Uses BSD sockets rather than NWListener: NWListener could not bind ::1 alongside 127.0.0.1
/// in the S1 spike, and BSD sockets let us set IPV6_V6ONLY explicitly.
public actor LoopbackListener {
    public nonisolated let port: UInt16
    private let server: Server

    private init(port: UInt16, fds: [Int32]) {
        self.port = port
        server = Server(port: port, fds: fds)
        let server = self.server
        Thread.detachNewThread { server.serve() }
    }

    public static func randomPort() -> UInt16 {
        var rng = SystemRandomNumberGenerator()
        return UInt16.random(in: 49152...65535, using: &rng)
    }

    public static func bind(maxAttempts: Int = 5, portPicker: () -> UInt16 = randomPort) async throws -> LoopbackListener {
        try await bind(maxAttempts: maxAttempts, portPicker: portPicker, binder: bindSocket)
    }

    static func bind(
        maxAttempts: Int,
        portPicker: () -> UInt16,
        binder: (Int32, UInt16) throws -> Int32
    ) async throws -> LoopbackListener {
        for _ in 0..<maxAttempts {
            guard let v4 = try? binder(AF_INET, portPicker()) else { continue }
            let p = boundPort(v4)
            guard p != 0, let v6 = try? binder(AF_INET6, p) else { Darwin.close(v4); continue }
            return LoopbackListener(port: p, fds: [v4, v6])
        }
        throw AuthError.portUnavailable
    }

    static func bindSocket(family: Int32, port: UInt16) throws -> Int32 {
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AuthError.portUnavailable }
        var one: Int32 = 1
        let rc: Int32
        if family == AF_INET6 {
            guard setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                Darwin.close(fd); throw AuthError.portUnavailable
            }
            var a = sockaddr_in6()
            a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = port.bigEndian
            a.sin6_addr = in6addr_loopback
            rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } }
        } else {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            a.sin_addr.s_addr = inet_addr("127.0.0.1")
            rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        }
        guard rc == 0, listen(fd, 8) == 0 else { Darwin.close(fd); throw AuthError.portUnavailable }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    static func boundPort(_ fd: Int32) -> UInt16 {
        var ss = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let ok = withUnsafeMutablePointer(to: &ss) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        guard ok == 0 else { return 0 }
        let family = ss.ss_family
        return withUnsafePointer(to: &ss) { p in
            family == sa_family_t(AF_INET6)
                ? p.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin6_port) }
                : p.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
        }
    }

    /// Waits for exactly one valid `GET /callback`; returns the code with any `#…` suffix removed.
    public func awaitCallback(expectedState: String, timeout: Duration = .seconds(300)) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        defer { server.closeAll() }
        while clock.now < deadline {
            if let q = server.captured {
                if q["error"] != nil { throw AuthError.cancelled }
                guard constantTimeEqual(q["state"] ?? "", expectedState) else { throw AuthError.stateMismatch }
                guard let code = q["code"].map(ClaudePKCEFlow.stripFragment), !code.isEmpty else { throw AuthError.cancelled }
                return code
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw AuthError.timeout
    }

    public func close() { server.closeAll() }
}

private final class Server: @unchecked Sendable {
    let port: UInt16
    private let lock = NSLock()
    private var fds: [Int32]
    private var handled = false
    private var query: [String: String]?

    static let page = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Agent Hourglass</title></head>"
        + "<body><p>Signed in. You can close this tab.</p></body></html>"

    init(port: UInt16, fds: [Int32]) { self.port = port; self.fds = fds }

    func closeAll() {
        lock.withLock { fds.forEach { Darwin.close($0) }; fds = [] }
    }

    var captured: [String: String]? { lock.withLock { query } }

    /// Accept loop; runs until the listener is closed. Answers every request, captures the first valid one.
    func serve() {
        while true {
            var pfds = lock.withLock { fds.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) } }
            if pfds.isEmpty { return }
            guard poll(&pfds, nfds_t(pfds.count), 100) > 0 else { continue }
            for p in pfds where p.revents & Int16(POLLIN) != 0 {
                let c = accept(p.fd, nil, nil)
                if c >= 0 { handle(c) }
            }
        }
    }

    private func handle(_ c: Int32) {
        defer { Darwin.close(c) }
        _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
        var one: Int32 = 1
        _ = setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = [UInt8](), buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 16384, !data.containsCRLFCRLF {
            let n = recv(c, &buf, buf.count, 0)
            if n <= 0 { break }
            data += buf[0..<n]
        }
        guard let head = String(bytes: data, encoding: .utf8)?.components(separatedBy: "\r\n\r\n").first,
              let q = validate(head) else {
            respond(c, "400 Bad Request", "bad request")
            return
        }
        respond(c, "200 OK", Self.page)
        lock.withLock { query = q }
    }

    /// Returns the query items of the first acceptable request, marking the listener handled.
    private func validate(_ head: String) -> [String: String]? {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let allowedHosts = ["localhost:\(port)", "127.0.0.1:\(port)", "[::1]:\(port)"]
        guard parts.count == 3, parts[0] == "GET",
              allowedHosts.contains(headers["host"]?.lowercased() ?? ""),
              (headers["content-length"] ?? "0") == "0", headers["transfer-encoding"] == nil,
              let comps = URLComponents(string: String(parts[1])), comps.path == "/callback"
        else { return nil }
        let first = lock.withLock { () -> Bool in
            defer { handled = true }
            return !handled
        }
        guard first else { return nil }
        return Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    private func respond(_ c: Int32, _ status: String, _ body: String) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n"
            + "Referrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        _ = resp.withCString { send(c, $0, strlen($0), 0) }
    }
}

private extension Array where Element == UInt8 {
    var containsCRLFCRLF: Bool {
        count >= 4 && (0...(count - 4)).contains { self[$0] == 13 && self[$0 + 1] == 10 && self[$0 + 2] == 13 && self[$0 + 3] == 10 }
    }
}
