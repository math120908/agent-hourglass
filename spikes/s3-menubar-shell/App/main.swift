import AppKit
import SwiftUI
import Security
import ServiceManagement

// Spike modes (args): --kc-write | --kc-read | --login-register | --login-status. No arg = menu bar UI.
let service = "cc.kuoc.claude-usage.spike"
let account = "spike-test-selfsigned"
let logURL = URL(fileURLWithPath: "/tmp/s3-spike.log")

func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

func kcWrite() {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    let data = "spike-value-\(Int(Date().timeIntervalSince1970))".data(using: .utf8)!
    var st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if st == errSecItemNotFound {
        var add = q; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        st = SecItemAdd(add as CFDictionary, nil)
        log("kc-write add status=\(st)")
    } else { log("kc-write update status=\(st)") }
}

func kcRead() {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &out)
    let v = (out as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
    log("kc-read status=\(st) value=\(v)")
}

func statusName(_ s: SMAppService.Status) -> String {
    switch s { case .notRegistered: "notRegistered"; case .enabled: "enabled"; case .requiresApproval: "requiresApproval"; case .notFound: "notFound"; @unknown default: "unknown" }
}

let args = CommandLine.arguments
if args.contains("--kc-write") { kcWrite(); exit(0) }
if args.contains("--kc-read") { kcRead(); exit(0) }
if args.contains("--login-register") {
    do { try SMAppService.mainApp.register(); log("login-register ok status=\(statusName(SMAppService.mainApp.status))") }
    catch { log("login-register error=\(error) status=\(statusName(SMAppService.mainApp.status))") }
    exit(0)
}
if args.contains("--login-unregister") {
    do { try SMAppService.mainApp.unregister(); log("login-unregister ok") } catch { log("login-unregister error=\(error)") }
    exit(0)
}
if args.contains("--login-status") { log("login-status=\(statusName(SMAppService.mainApp.status))"); exit(0) }

func renderIcon(percent: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: 30, height: 22), flipped: false) { r in
        let font = NSFont.boldSystemFont(ofSize: 7)
        ("5H" as NSString).draw(at: NSPoint(x: 1, y: 12), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 28, height: 6), xRadius: 2, yRadius: 2)
        NSColor.black.setStroke(); outline.lineWidth = 1; outline.stroke()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 28 * percent, height: 6), xRadius: 2, yRadius: 2).fill()
        return true
    }
    img.isTemplate = true
    return img
}

struct FakeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage").font(.headline)
            Text("All accounts updated 14:31").font(.caption).foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: "sparkle").foregroundStyle(.orange); Text("claude #1"); Spacer(); Text("62%") }
                    ProgressView(value: 0.62).tint(.orange)
                    Text("Session resets in 2h 14m").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding().frame(width: 340)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = renderIcon(percent: 0.62)
        item.button?.action = #selector(toggle)
        item.button?.target = self
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FakeCard())
        log("ui launched build=17925089233")
        if ProcessInfo.processInfo.environment["S3_OPEN_POPOVER"] == "1" || args.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.toggle() }
        }
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let b = item.button { popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
