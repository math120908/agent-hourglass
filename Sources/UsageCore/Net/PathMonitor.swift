import Foundation
import Network

/// Wraps `NWPathMonitor` as a stream of "online" flags (`path.status == .satisfied`).
public enum PathMonitor {
    public static func updates(queue: DispatchQueue = DispatchQueue(label: "cc.kuoc.claude-usage.path")) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: queue)
        }
    }
}
