#if DEBUG
import SwiftUI
import UIKit
import UsageCore

/// Hosts each scene in a real window (ImageRenderer draws UIKit-backed views as placeholders)
/// and writes `<scene>-<theme>-<light|dark>.png` at 3x.
enum SnapshotRenderer {
    @MainActor static func render(_ scenes: [SnapshotScene], to dir: URL, log: (String) -> Void) async -> Int {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var count = 0
        for scene in scenes {
            for theme in scene.themes {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    let name = "\(scene.name)-\(theme.rawValue)-\(style == .dark ? "dark" : "light")"
                    guard let data = await snapshot(scene, theme: theme, style: style) else {
                        log("render failed name=\(name)")
                        continue
                    }
                    do {
                        try data.write(to: dir.appending(path: "\(name).png"))
                        count += 1
                    } catch {
                        log("render write failed name=\(name)")
                    }
                }
            }
        }
        return count
    }

    @MainActor private static func snapshot(_ scene: SnapshotScene, theme: Theme, style: UIUserInterfaceStyle) async -> Data? {
        let host = UIHostingController(rootView: AnyView(scene.make(theme).environment(\.appTheme, theme)))
        host.overrideUserInterfaceStyle = style
        host.safeAreaRegions = []  // snapshots are laid out edge to edge; no status-bar inset
        let size: CGSize
        switch scene.size {
        case .device:
            size = SnapshotSize.deviceSize
        case .fitting(let width):
            let fit = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            size = CGSize(width: width, height: max(1, ceil(fit.height)))
        }
        let rect = CGRect(origin: .zero, size: size)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let ws = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        let window = UIWindow(windowScene: ws)
        window.frame = rect
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = rect
        host.view.backgroundColor = .systemBackground
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))  // let materials settle
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: rect, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image.pngData()
    }
}
#endif
