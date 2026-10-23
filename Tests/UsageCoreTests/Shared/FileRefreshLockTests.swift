import Foundation
import Testing
@testable import UsageCore

private actor Recorder {
    var intervals: [(ContinuousClock.Instant, ContinuousClock.Instant)] = []
    func add(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) { intervals.append((a, b)) }
}

private struct Boom: Error {}

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
        let url = url
        let holder = Task {
            try await FileRefreshLock(url: url).withLock { try await Task.sleep(for: .seconds(2)) }
        }
        try await Task.sleep(for: .milliseconds(100))
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
        try await FileRefreshLock(url: url, timeout: .milliseconds(200)).withLock {}
        #expect(ContinuousClock.now - t0 < .milliseconds(200))
    }

    @Test func releasedAfterCancellation() async throws {
        try await cancelThenReacquire(within: .seconds(1))
    }

    @Test func cancelledBodyReleasesLock() async throws {
        try await cancelThenReacquire(within: .milliseconds(200))
    }

    private func cancelThenReacquire(within limit: Duration) async throws {
        let url = url
        let task = Task {
            try await FileRefreshLock(url: url).withLock { try await Task.sleep(for: .seconds(30)) }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let t0 = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: limit).withLock {}
        #expect(ContinuousClock.now - t0 < limit)
        _ = await task.result
    }

    @Test func slowBodyTimesOutAndReleases() async throws {
        let t0 = ContinuousClock.now
        await #expect(throws: FileRefreshLockError.timeout) {
            try await FileRefreshLock(url: url, timeout: .milliseconds(300)).withLock {
                try await Task.sleep(for: .seconds(30))
            }
        }
        #expect(ContinuousClock.now - t0 < .seconds(2))
        try await FileRefreshLock(url: url, timeout: .milliseconds(200)).withLock {}
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
    private func spawnHolder(sleep seconds: Int) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [
            "-MFcntl=:flock",
            "-e",
            "open(F,\">>\",$ARGV[0]) or die; flock(F,LOCK_EX) or die; $|=1; print \"locked\\n\"; sleep \(seconds)",
            url.path,
        ]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        var buf = Data()
        while !(String(decoding: buf, as: UTF8.self).contains("locked\n")) {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { throw Boom() }
            buf.append(chunk)
        }
        return p
    }

    @Test func separateProcessHolderBlocksUntilReleased() async throws {
        let p = try spawnHolder(sleep: 1)
        defer { p.terminate() }
        let t0 = ContinuousClock.now
        let t1 = try await FileRefreshLock(url: url).withLock { ContinuousClock.now }
        #expect(t1 - t0 >= .milliseconds(800))
    }

    @Test func killedHolderReleasesLock() async throws {
        let p = try spawnHolder(sleep: 30)
        kill(p.processIdentifier, SIGKILL)
        let t0 = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: .seconds(1)).withLock {}
        #expect(ContinuousClock.now - t0 < .seconds(1))
    }

    @Test func timesOutWhenHeld() async throws {
        let p = try spawnHolder(sleep: 5)
        defer { p.terminate() }
        await #expect(throws: FileRefreshLockError.timeout) {
            try await FileRefreshLock(url: url, timeout: .milliseconds(300)).withLock {}
        }
    }
    #endif
}
