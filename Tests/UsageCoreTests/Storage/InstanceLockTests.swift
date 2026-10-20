import Foundation
import Testing
@testable import UsageCore

struct InstanceLockTests {
    func tempDir() throws -> URL {
        try AppSupport.directory(base: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func secondAcquireFails() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let url = dir.appendingPathComponent("instance.lock")
        let first = try InstanceLock.acquire(at: url)
        #expect(throws: InstanceLock.Error.alreadyRunning) { _ = try InstanceLock.acquire(at: url) }
        withExtendedLifetime(first) {}
    }

    @Test func lockFileIs0600() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let lock = try InstanceLock.acquire(in: dir)
        let mode = (try FileManager.default.attributesOfItem(atPath: lock.url.path)[.posixPermissions] as! NSNumber).intValue
        #expect(mode == 0o600)
        #expect(lock.url.lastPathComponent == "instance.lock")
    }

    @Test func releaseOnDeinit() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let url = dir.appendingPathComponent("instance.lock")
        var first: InstanceLock? = try InstanceLock.acquire(at: url)
        #expect(first != nil)
        first = nil
        let second = try InstanceLock.acquire(at: url)
        withExtendedLifetime(second) {}
    }
}

extension InstanceLockTests {
    /// Cross-process: a child process holding the flock makes our acquire fail.
    @Test func otherProcessHoldsLock() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let url = dir.appendingPathComponent("instance.lock")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-e", "use Fcntl qw(:flock); open(my $f, '>>', $ARGV[0]) or die; flock($f, LOCK_EX) or die; print \"ok\\n\"; $|=1; sleep 30", url.path]
        let out = Pipe()
        child.standardOutput = out
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        _ = out.fileHandleForReading.availableData // wait for "ok"
        #expect(throws: InstanceLock.Error.alreadyRunning) { _ = try InstanceLock.acquire(at: url) }
        child.terminate(); child.waitUntilExit()
        let mine = try InstanceLock.acquire(at: url)
        withExtendedLifetime(mine) {}
    }

    @Test func pathMonitorEmits() async {
        var it = PathMonitor.updates().makeAsyncIterator()
        #expect(await it.next() != nil)
    }
}
