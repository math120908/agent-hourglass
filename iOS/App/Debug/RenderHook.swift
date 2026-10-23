#if DEBUG
import OSLog
import SwiftUI

/// Renders `SnapshotCatalog.all` to PNG when launched with `--render <subdir>`, then exits.
enum RenderHook {
    private static let logger = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Shell")

    @MainActor static func runIfRequested() async -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render"), i + 1 < args.count else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appending(path: "renders/\(args[i + 1])/app", directoryHint: .isDirectory)
        let count = await SnapshotRenderer.render(SnapshotCatalog.all, to: dir) { logger.error("\($0, privacy: .public)") }
        logger.notice("render done count=\(count)")
        exit(0)
    }
}
#endif
