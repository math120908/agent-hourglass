#if DEBUG
import OSLog
import SwiftUI
import UsageCore

/// Renders registered views to PNG when launched with `--render <subdir>`.
enum RenderHook {
    struct Job {
        let name: String
        let view: @MainActor () -> AnyView
        let size: CGSize
    }

    private static let logger = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Shell")

    @MainActor static var jobs: [Job] = [
        Job(name: "shell-accounts", view: { AnyView(AccountListView(lines: sampleLines)) }, size: CGSize(width: 393, height: 852)),
    ]

    private static let sampleLines: [ShellStatusLine] = [
        ShellStatusLine(id: AccountID(kind: .claude, remoteID: "sample-work"), name: "Work", kind: .claude, snapshotAge: 120, hasCredential: true, text: "Work (claude) | snapshot 2m ago | key ok"),
        ShellStatusLine(id: AccountID(kind: .codex, remoteID: "sample-home"), name: "Home", kind: .codex, snapshotAge: nil, hasCredential: false, text: "Home (codex) | no snapshot | no key"),
    ]

    /// ImageRenderer draws UIKit-backed views (List, NavigationStack) as a placeholder,
    /// so host the view in an offscreen window and snapshot it instead.
    @MainActor private static func snapshot(_ job: Job) -> Data? {
        let rect = CGRect(origin: .zero, size: job.size)
        let host = UIHostingController(rootView: job.view())
        let window = UIWindow(frame: rect)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = rect
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: job.size, format: format).image { _ in
            host.view.drawHierarchy(in: rect, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image.pngData()
    }

    @MainActor static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render"), i + 1 < args.count else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appending(path: "renders/\(args[i + 1])", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var count = 0
        for job in jobs {
            guard let data = snapshot(job) else {
                logger.error("render failed name=\(job.name, privacy: .public)")
                continue
            }
            do {
                try data.write(to: dir.appending(path: "\(job.name).png"))
                count += 1
            } catch {
                logger.error("render write failed name=\(job.name, privacy: .public)")
            }
        }
        logger.notice("render done count=\(count)")
        return true
    }
}
#endif
