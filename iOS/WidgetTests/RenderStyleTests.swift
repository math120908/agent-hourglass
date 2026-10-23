import SwiftUI
import UIKit
import UsageCore
import XCTest

final class RenderStyleTests: XCTestCase {
    private func style(_ mode: WidgetRenderMode, accent: Color? = nil) -> WidgetRenderStyle {
        WidgetRenderStyle(mode: mode, theme: .glass, colorScheme: .light, previewAccent: accent)
    }

    private func rgba(_ c: Color) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    func testFillIsWhiteWhenAccented() {
        XCTAssertEqual(rgba(style(.accented).fill(.normal, .claude)), rgba(.white))
        XCTAssertEqual(rgba(style(.vibrant).fill(.critical, .codex)), rgba(.white))
    }

    func testFillUsesPaletteWhenFullColor() {
        XCTAssertEqual(rgba(style(.fullColor).fill(.normal, .claude)), rgba(GlassStyle.color(.normal, .claude)))
        XCTAssertEqual(rgba(style(.fullColor).fill(.critical, .codex)), rgba(GlassStyle.critical))
    }

    func testPreviewAccentOverridesInAccented() {
        XCTAssertEqual(rgba(style(.accented, accent: .blue).fill(.normal, .claude)), rgba(.blue))
    }

    func testTrackVisibleInAccented() {
        XCTAssertGreaterThan(rgba(style(.accented).track())[3], 0)
        XCTAssertGreaterThan(rgba(style(.vibrant).track())[3], 0)
    }

    func testDimmed() {
        XCTAssertEqual(style(.fullColor).dimmed(false), 1.0)
        XCTAssertEqual(style(.fullColor).dimmed(true), 0.45)
    }
}
