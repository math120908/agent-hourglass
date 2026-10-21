import Foundation
import Testing
@testable import UsageCore

private let fakeToken = "gho_" + String(repeating: "x", count: 36)

private struct FakeGh {
    let dir: URL
    var path: String { dir.appendingPathComponent("gh").path }

    init(_ body: String, mode: Int = 0o755) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fakegh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nD='\(dir.path)'\n" + fakeScriptWarmupGuard + body + "\n"
        try script.write(toFile: dir.appendingPathComponent("gh").path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: dir.appendingPathComponent("gh").path)
        try warmUpFakeScript(at: path)
    }

    func source(timeout: Duration = .seconds(10)) -> GhTokenSource {
        GhTokenSource(candidates: [dir.appendingPathComponent("nope").path, path], timeout: timeout)
    }

    func read(_ name: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }
}

struct GhTokenSourceTests {
    @Test func pathIgnored() async throws {
        // Only fixed candidates are consulted; a gh on $PATH is never used.
        let src = GhTokenSource(candidates: ["/nonexistent/a/gh", "/nonexistent/b/gh"])
        await #expect(throws: GhError.missing) { try await src.logins() }
        await #expect(throws: GhError.missing) { try await src.token(for: "alice") }
    }

    @Test func worldWritableRefused() async throws {
        let gh = try FakeGh("echo \(fakeToken)", mode: 0o777)
        await #expect(throws: GhError.untrusted) { try await gh.source().token(for: "alice") }
        let gw = try FakeGh("echo \(fakeToken)", mode: 0o775)
        await #expect(throws: GhError.untrusted) { try await gw.source().token(for: "alice") }
    }

    @Test func symlinkResolvedAndChecked() async throws {
        let gh = try FakeGh("echo \(fakeToken)", mode: 0o777)
        let link = gh.dir.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: gh.path)
        await #expect(throws: GhError.untrusted) { try await GhTokenSource(candidates: [link]).token(for: "a") }
    }

    @Test func tokenFromStdoutOnly() async throws {
        let gh = try FakeGh("echo gho_stderrtoken >&2\necho \(fakeToken)")
        let t = try await gh.source().token(for: "alice")
        #expect(t.reveal() == fakeToken)
        let errOnly = try FakeGh("echo \(fakeToken) >&2")
        await #expect(throws: GhError.loginRemoved) { try await errOnly.source().token(for: "alice") }
    }

    @Test func childEnvHasNoToken() async throws {
        let gh = try FakeGh("env > \"$D/env\"\necho \(fakeToken)")
        _ = try await gh.source().token(for: "alice")
        let env = gh.read("env")
        #expect(!env.contains(fakeToken) && !env.contains("gho_"))
        let keys = Set(env.split(separator: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(keys.isSuperset(of: ["HOME", "USER", "PATH"]))
        #expect(keys.subtracting(["HOME", "USER", "PATH", "PWD", "SHLVL", "OLDPWD", "_"]).isEmpty)
        #expect(env.contains("PATH=/usr/bin:/bin\n"))
    }

    @Test func argvHasNoToken() async throws {
        let gh = try FakeGh("echo \"$@\" > \"$D/argv\"\necho \(fakeToken)")
        _ = try await gh.source().token(for: "alice")
        #expect(gh.read("argv") == "auth token --user alice\n")
    }

    @Test func timeoutKillsChild() async throws {
        let gh = try FakeGh("echo $$ > \"$D/pid\"\nexec sleep 30")
        let start = Date()
        await #expect(throws: GhError.timeout) { try await gh.source(timeout: .seconds(2)).token(for: "alice") }
        #expect(Date().timeIntervalSince(start) < 5)
        // The pid file is written by the child; under parallel load it can land just after the
        // timeout fires, so poll briefly instead of reading once.
        var pidText = ""
        for _ in 0..<50 where pidText.isEmpty {
            pidText = gh.read("pid").trimmingCharacters(in: .whitespacesAndNewlines)
            if pidText.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        let pid = try #require(pid_t(pidText))
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test func noisyStdoutParsed() async throws {
        let gh = try FakeGh("echo 'A new release of gh is available: 2.40 -> 2.60'\necho\necho \(fakeToken)\necho")
        #expect(try await gh.source().token(for: "alice").reveal() == fakeToken)
        let noise = try FakeGh("echo 'A new release of gh is available'")
        await #expect(throws: GhError.loginRemoved) { try await noise.source().token(for: "alice") }
    }

    @Test func unknownLoginIsLoginRemoved() async throws {
        let gh = try FakeGh("echo 'no account found for user bob' >&2\nexit 1")
        await #expect(throws: GhError.loginRemoved) { try await gh.source().token(for: "bob") }
    }

    @Test func tokenCachedUntilInvalidated() async throws {
        let gh = try FakeGh("echo x >> \"$D/calls\"\necho \(fakeToken)")
        let src = gh.source()
        _ = try await src.token(for: "alice")
        _ = try await src.token(for: "alice")
        #expect(gh.read("calls") == "x\n")
        src.invalidate("alice")
        _ = try await src.token(for: "alice")
        #expect(gh.read("calls") == "x\nx\n")
    }

    @Test func loginsParsed() async throws {
        let gh = try FakeGh("""
        cat <<'OUT'
        github.com
          ✓ Logged in to github.com account pikachu-dev (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'gist', 'read:org', 'repo', 'workflow'

          ✓ Logged in to github.com account eevee-lab (keyring)
          - Active account: false
        OUT
        """)
        #expect(try await gh.source().logins() == ["pikachu-dev", "eevee-lab"])
    }
}
