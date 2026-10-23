import Foundation
import Testing
@testable import UsageCore

private actor Recorder {
    var intervals: [(ContinuousClock.Instant, ContinuousClock.Instant)] = []
    func add(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) { intervals.append((a, b)) }
}

private struct Boom: Error {}

private actor Flag {
    var value = false
    func set() { value = true }
}

/// Generous lock timeout for "is the lock free again" checks. A released lock is taken on the first
/// non-blocking `flock`, so elapsed time stays far below this even under heavy load; a lock that is
/// never released (or released only when the holder's own 15 s timeout fires) makes `acquire` spin
/// to this timeout and throw `.timeout`, and the `< reacquireTimeout / 2` bound catches a late release.
private let reacquireTimeout: Duration = .seconds(10)

/// Runs `FileRefreshLock.withLock` in a task whose body signals once the lock is held and then
/// sleeps until cancelled, so tests wait on the event instead of a fixed head start.
private func startHolder(url: URL) async -> Task<Void, Error> {
    let (held, cont) = AsyncStream<Void>.makeStream()
    let task = Task {
        try await FileRefreshLock(url: url).withLock {
            cont.yield()
            try await Task.sleep(for: .seconds(30))
        }
    }
    for await _ in held { break }
    return task
}

struct FileRefreshLockTests {
    let dir: URL
    let url: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("refresh.lock")
    }

    @Test func twoInstancesSameFileDoNotOverlap() async throws {
        let rec = Recorder()
        let url = url
        async let a: Void = FileRefreshLock(url: url).withLock {
            let s = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(200))
            await rec.add(s, .now)
        }
        async let b: Void = FileRefreshLock(url: url).withLock {
            let s = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(200))
            await rec.add(s, .now)
        }
        _ = try await (a, b)
        let iv = await rec.intervals.sorted { $0.0 < $1.0 }
        #expect(iv.count == 2)
        #expect(iv[0].1 <= iv[1].0)
    }

    @Test func timesOutWhenHeldInProcess() async throws {
        let holder = await startHolder(url: url)
        await #expect(throws: FileRefreshLockError.timeout) {
            try await FileRefreshLock(url: url, timeout: .milliseconds(300)).withLock {}
        }
        holder.cancel()
    }

    @Test func releasedAfterBodyThrows() async throws {
        await #expect(throws: Boom.self) {
            try await FileRefreshLock(url: url).withLock { throw Boom() }
        }
        let t0 = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: reacquireTimeout).withLock {}
        #expect(ContinuousClock.now - t0 < reacquireTimeout / 2)
    }

    @Test func releasedAfterCancellation() async throws {
        let task = await startHolder(url: url)
        task.cancel()
        let t0 = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: reacquireTimeout).withLock {}
        #expect(ContinuousClock.now - t0 < reacquireTimeout / 2)
        _ = await task.result
    }

    @Test func cancelledBodyReleasesLock() async throws {
        // The holder must end by cancellation (not by its own 15 s lock timeout), and the lock
        // must be free once it has ended.
        let task = await startHolder(url: url)
        let t0 = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - t0 < reacquireTimeout / 2)
        try await FileRefreshLock(url: url, timeout: .milliseconds(1)).withLock {}
    }

    @Test func slowBodyTimesOutAndReleases() async throws {
        // Bound against the body's 30 s sleep: the 300 ms timeout must cut the body, so elapsed
        // stays far below the sleep even when the machine is busy.
        let bodySleep: Duration = .seconds(30)
        let t0 = ContinuousClock.now
        await #expect(throws: FileRefreshLockError.timeout) {
            try await FileRefreshLock(url: url, timeout: .milliseconds(300)).withLock {
                try await Task.sleep(for: bodySleep)
            }
        }
        #expect(ContinuousClock.now - t0 < bodySleep / 2)
        try await FileRefreshLock(url: url, timeout: .milliseconds(1)).withLock {}
    }

    @Test func lockFileIs0600() async throws {
        try await FileRefreshLock(url: url).withLock {}
        let mode = try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
        #expect(mode == 0o600)
    }

    @Test func createsMissingDirectory0700() async throws {
        let nested = dir.appendingPathComponent("sub").appendingPathComponent("refresh.lock")
        try await FileRefreshLock(url: nested).withLock {}
        let mode = try (FileManager.default.attributesOfItem(atPath: nested.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber).intValue
        #expect(mode == 0o700)
    }

    @Test func symlinkAtLockPathIsRefused() async throws {
        let target = dir.appendingPathComponent("target")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        await #expect(throws: FileRefreshLockError.open(errno: ELOOP)) {
            try await FileRefreshLock(url: url).withLock {}
        }
    }

    @Test func directoryAtLockPathIsRefused() async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await #expect(throws: FileRefreshLockError.self) {
            try await FileRefreshLock(url: url).withLock {}
        }
    }

    #if os(macOS)
    private struct Holder {
        let process: Process
        let stdin: Pipe

        /// Lets the holder exit (and the kernel drop its flock) on demand.
        func release() { try? stdin.fileHandleForWriting.write(contentsOf: Data("go\n".utf8)) }
    }

    /// Spawns a separate process that takes the flock and holds it until `release()` or `seconds`.
    private func spawnHolder(maxHold seconds: Int) throws -> Holder {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [
            "-MFcntl=:flock",
            "-e",
            "open(F,\">>\",$ARGV[0]) or die; flock(F,LOCK_EX) or die; $|=1; print \"locked\\n\"; alarm \(seconds); <STDIN>",
            url.path,
        ]
        let pipe = Pipe()
        let stdin = Pipe()
        p.standardOutput = pipe
        p.standardInput = stdin
        try p.run()
        var buf = Data()
        while !(String(decoding: buf, as: UTF8.self).contains("locked\n")) {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { throw Boom() }
            buf.append(chunk)
        }
        return Holder(process: p, stdin: stdin)
    }

    @Test func separateProcessHolderBlocksUntilReleased() async throws {
        // Ordered by events, not wall clock: the holder keeps the flock until told to exit, so the
        // body may only run after `released` was set. 300 ms gives a broken lock time to slip in.
        let h = try spawnHolder(maxHold: 30)
        defer { h.process.terminate() }
        let released = Flag()
        let url = url
        async let acquiredAfterRelease = FileRefreshLock(url: url, timeout: reacquireTimeout).withLock {
            await released.value
        }
        try await Task.sleep(for: .milliseconds(300))
        await released.set()
        h.release()
        #expect(try await acquiredAfterRelease)
    }

    @Test func killedHolderReleasesLock() async throws {
        let h = try spawnHolder(maxHold: 30)
        kill(h.process.processIdentifier, SIGKILL)
        // Bound against the lock timeout, not a tight wall clock: if the kernel did not release
        // the dead holder's flock, acquire would spin until `timeout` and throw `.timeout`.
        // Under heavy load reaping the holder alone can take >1 s, so keep the margin wide.
        let t0 = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: reacquireTimeout).withLock {}
        #expect(ContinuousClock.now - t0 < reacquireTimeout / 2)
    }

    @Test func timesOutWhenHeld() async throws {
        let h = try spawnHolder(maxHold: 30)
        defer { h.process.terminate() }
        await #expect(throws: FileRefreshLockError.timeout) {
            try await FileRefreshLock(url: url, timeout: .milliseconds(300)).withLock {}
        }
    }
    #endif
}
