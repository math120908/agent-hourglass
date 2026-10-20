import Foundation
import Testing
@testable import UsageCore

struct AppSupportTests {
    func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @Test func dirIs0700FilesAre0600() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = try AppSupport.directory(base: base)
        #expect(dir.lastPathComponent == "cc.kuoc.claude-usage")
        #expect(try mode(dir) == 0o700)
        let file = dir.appendingPathComponent("state.json")
        try AppSupport.secureWrite(Data("{}".utf8), to: file)
        #expect(try mode(file) == 0o600)
        try AppSupport.secureWrite(Data("{\"a\":1}".utf8), to: file)
        #expect(try mode(file) == 0o600)
        #expect(try Data(contentsOf: file) == Data("{\"a\":1}".utf8))
        // existing loose dir gets tightened
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        _ = try AppSupport.directory(base: base)
        #expect(try mode(dir) == 0o700)
    }
}
