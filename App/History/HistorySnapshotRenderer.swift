import AppKit
import SwiftUI
import UsageCore

/// Debug: writes history-<range>-<mode>.png (instr-history-* for Instrument) and history-empty-light.png from a seeded in-memory store.
@MainActor
enum HistorySnapshotRenderer {
    /// `AgentHourglass --render-history <dir> [--theme instrument]`.
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-history"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            let t = args.firstIndex(of: "--theme").flatMap { $0 + 1 < args.count ? Theme(rawValue: args[$0 + 1]) : nil } ?? .glass
            await render(to: dir, theme: t)
            exit(0)
        }
        RunLoop.main.run()
    }

    static func render(to dir: URL, theme: Theme = .glass) async {
        guard let store = try? HistoryStore.inMemory() else { return }
        let now = Fixtures.now
        let id = AccountID(kind: .claude, remoteID: "happy-hippo")
        await seed(store, id: id, now: now)
        let entry = AccountEntry(id: id, kind: .claude, displayName: "Snorlax", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
        let cases: [(String, HistoryRange, Int)] = [("24h", .day, 0), ("7d", .week, 0), ("empty", .day, 40)]
        for (name, range, offset) in cases {
            for (mode, ap) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                if theme == .glass && name == "empty" && mode == "dark" { continue }
                let model = HistoryModel(store: store, now: { now })
                model.range = range
                model.hiddenModels = name == "7d" ? [] : ["Fable"]
                model.show(entries: [entry])
                model.offset = offset
                try? await Task.sleep(for: .milliseconds(400))
                let h = name == "empty" ? nil : now.addingTimeInterval(-range.seconds * 0.27)
                let prefix = theme == .glass ? "history" : "instr-history"
                write(HistoryView(model: model, theme: theme, hover: h), ap, dir.appendingPathComponent("\(prefix)-\(name)-\(mode).png"))
            }
        }
    }

    /// 7 days of 15-minute samples: sawtooth session windows, slow weekly climb, a Fable model line.
    private static func seed(_ store: HistoryStore, id: AccountID, now: Date) async {
        let start = now.addingTimeInterval(-7 * 86_400)
        var session = 0.0, weekly = 18.0, fable = 9.0
        var windowEnd = start.addingTimeInterval(5 * 3600)
        for i in 0...(7 * 96) {
            let t = start.addingTimeInterval(Double(i) * 900)
            if t >= windowEnd { session = 0; windowEnd = t.addingTimeInterval(5 * 3600) }
            let hour = Calendar.current.component(.hour, from: t)
            let active = (9..<13).contains(hour) || (15..<19).contains(hour) || (21..<23).contains(hour)
            if active {
                session = min(session + (i % 3 == 0 ? 7 : 2.5), i / 96 == 3 ? 94 : 82)
                weekly = min(weekly + 0.06, 39); fable = min(fable + 0.03, 21)
            }
            let snap = UsageSnapshot(accountID: id, fetchedAt: t, meters: [
                Meter(kind: .session5h, label: "Session", percentUsed: session, resetsAt: windowEnd),
                Meter(kind: .weeklyAll, label: "All models", percentUsed: (weekly * 2).rounded() / 2, resetsAt: Fixtures.weeklyReset),
                Meter(kind: .weeklyModel, label: "Fable", percentUsed: fable.rounded(), resetsAt: Fixtures.weeklyReset),
            ])
            try? await store.record(snap)
        }
    }

    private static func write(_ view: some View, _ ap: NSAppearance.Name, _ url: URL) {
        let host = NSHostingView(rootView: view.frame(width: 760, height: 460))
        host.appearance = NSAppearance(named: ap)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 460)
        let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.appearance = host.appearance
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
