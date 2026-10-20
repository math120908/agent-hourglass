import Foundation
import UsageCore

/// One soak log line per fetch. Holds only timestamps, status, HTTP code and percentages: never a token.
enum SoakLine {
    /// HTTP code implied by the outcome. AccountClient does not surface the raw code, so non-200s are derived.
    static func httpCode(_ outcome: FetchOutcome) -> String {
        switch outcome {
        case .success: return "200"
        case .failure(.rateLimited): return "429"
        case .failure(.needsLogin): return "401"
        case .failure: return "-"
        }
    }

    static func status(_ outcome: FetchOutcome) -> String {
        switch outcome {
        case .success: return "fresh"
        case let .failure(s):
            switch s {
            case .rateLimited: return "rateLimited"
            default: return String(describing: s)
            }
        }
    }

    static func percent(_ snap: UsageSnapshot?, _ kind: Meter.Kind) -> String {
        guard let p = snap?.meters.first(where: { $0.kind == kind })?.percentUsed else { return "-" }
        return String(format: "%.1f", p)
    }

    static func format(at: Date, outcome: FetchOutcome, count429: Int) -> String {
        let snap: UsageSnapshot? = if case let .success(s) = outcome { s } else { nil }
        let ts = ISO8601DateFormatter().string(from: at)
        return "\(ts) status=\(status(outcome)) http=\(httpCode(outcome)) session=\(percent(snap, .session5h)) weekly=\(percent(snap, .weeklyAll)) n429=\(count429)"
    }
}

/// Append-only log file forced to 0600.
final class SoakLogFile: @unchecked Sendable {
    let url: URL
    private let fd: Int32
    private let lock = NSLock()

    init(url: URL) throws {
        let fd = open(url.path, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard fchmod(fd, 0o600) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.url = url
        self.fd = fd
    }

    func append(_ line: String) {
        let data = Array((line + "\n").utf8)
        lock.withLock { _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }
    }

    deinit { close(fd) }
}
