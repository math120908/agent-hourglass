import SwiftUI
import UIKit
import UsageCore
import XCTest

/// Renders every widget family x theme x mode, plus states and settings variants, to `RENDER_OUT`.
@MainActor
final class RenderMatrixTests: XCTestCase {
    typealias F = WidgetFixtures

    enum Family: String, CaseIterable {
        case small, circular, rectangular, inline

        var size: CGSize {
            switch self {
            case .small: CGSize(width: 170, height: 170)
            case .circular: CGSize(width: 76, height: 76)
            case .rectangular: CGSize(width: 172, height: 76)
            case .inline: CGSize(width: 257, height: 26)
            }
        }
    }

    struct Mode {
        var name: String
        var render: WidgetRenderMode
        var scheme: ColorScheme
        var accent: Color?
        var backdrop: Backdrop
    }

    struct Case {
        var name: String
        var family: Family
        var mode: Mode
        var entry: UsageEntry
    }

    static let smallModes = [
        Mode(name: "fullcolor-light", render: .fullColor, scheme: .light, accent: nil, backdrop: .homeLight),
        Mode(name: "fullcolor-dark", render: .fullColor, scheme: .dark, accent: nil, backdrop: .homeDark),
        Mode(name: "accented-tinted", render: .accented, scheme: .dark, accent: .cyan, backdrop: .tinted(.cyan)),
        Mode(name: "accented-clear", render: .accented, scheme: .dark, accent: .white, backdrop: .clear),
    ]
    static let vibrant = Mode(name: "vibrant", render: .vibrant, scheme: .dark, accent: nil, backdrop: .lockScreen)

    static func themeName(_ t: Theme) -> String { t == .glass ? "glass" : "instrument" }

    static var matrix: [Case] {
        var cases: [Case] = []
        for family in Family.allCases {
            for theme in [Theme.glass, .instrument] {
                for mode in family == .small ? smallModes : [vibrant] {
                    let name = "\(family.rawValue)-\(themeName(theme))-\(mode.name)"
                    cases.append(Case(name: name, family: family, mode: mode, entry: F.entry(F.claudeMax, theme: theme)))
                }
            }
        }
        let states: [(String, UsageEntry)] = [
            ("stale", F.entry(F.claudeStale, status: .stale)),
            ("needslogin", F.entry(F.claudeMax, status: .needsLogin)),
            ("afterreset", F.entry(F.claudeAfterReset)),
            ("empty", F.entry(nil, account: nil, status: nil)),
            ("codex", F.entry(F.codexPlus, account: F.codexAccount)),
        ]
        for family in Family.allCases {
            let mode = family == .small ? smallModes[1] : vibrant
            for (state, entry) in states {
                cases.append(Case(name: "\(family.rawValue)-glass-\(mode.name)-\(state)", family: family, mode: mode, entry: entry))
            }
        }
        var remaining = DisplaySettings.default
        remaining.showRemaining = true
        var countdown = DisplaySettings.default
        countdown.resetStyle = .countdown
        var hour24 = DisplaySettings.default
        hour24.hour24 = .on
        for (variant, settings) in [("remaining", remaining), ("countdown", countdown), ("24h", hour24)] {
            cases.append(Case(name: "small-glass-fullcolor-dark-\(variant)", family: .small, mode: smallModes[1], entry: F.entry(F.claudeMax, settings: settings)))
        }
        return cases
    }

    @ViewBuilder
    static func view(_ c: Case) -> some View {
        let style = WidgetRenderStyle(mode: c.mode.render, theme: c.entry.theme, colorScheme: c.mode.scheme, previewAccent: c.mode.accent)
        Group {
            switch c.family {
            case .small:
                Group {
                    switch c.entry.theme {
                    case .glass: SmallGlassView(entry: c.entry, style: style)
                    case .instrument: SmallInstrumentView(entry: c.entry, style: style)
                    }
                }
                .padding(16)
                .frame(width: c.family.size.width, height: c.family.size.height)
                .background { if style.isFullColor { WidgetBackground(style: style) } }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            case .circular: CircularUsageView(entry: c.entry, style: style)
            case .rectangular: RectangularUsageView(entry: c.entry, style: style).padding(.horizontal, 2)
            case .inline: InlineUsageView(entry: c.entry, style: style).font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundStyle(c.mode.render == .fullColor ? (c.mode.scheme == .dark ? Color.white : Color.black) : (c.mode.accent ?? .white))
        .environment(\.colorScheme, c.mode.scheme)
    }

    func testRenderAll() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("RENDER_OUT not set; run make render-widgets")
        }
        let dir = URL(fileURLWithPath: out)
        let cases = Self.matrix
        XCTAssertEqual(cases.count, 37)
        XCTAssertEqual(Set(cases.map(\.name)).count, 37)
        for c in cases {
            let url = dir.appendingPathComponent("\(c.name).png")
            try RenderHarness.render(Self.view(c), size: c.family.size, backdrop: c.mode.backdrop, to: url)
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty, c.name)
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage, c.name)
            XCTAssertEqual(image.width, Int(c.family.size.width * RenderHarness.scale), c.name)
            XCTAssertEqual(image.height, Int(c.family.size.height * RenderHarness.scale), c.name)
            if c.mode.render != .fullColor {
                let back = try XCTUnwrap(RenderHarness.backdropImage(c.mode.backdrop, size: c.family.size))
                let ratio = Self.differingRatio(image, back)
                XCTAssertGreaterThanOrEqual(ratio, c.mode.render == .accented ? 0.05 : 0.01, "\(c.name): widget nearly invisible (\(ratio))")
            }
        }
    }

    /// Fraction of pixels that differ from the backdrop by more than a small threshold.
    static func differingRatio(_ a: CGImage, _ b: CGImage) -> Double {
        let pa = rgba(a), pb = rgba(b)
        guard pa.count == pb.count, !pa.isEmpty else { return 0 }
        var diff = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
            if d > 24 { diff += 1 }
        }
        return Double(diff) / Double(pa.count / 4)
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buf
    }
}
