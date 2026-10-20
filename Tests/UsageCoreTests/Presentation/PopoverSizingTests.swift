import Testing
@testable import UsageCore

struct PopoverSizingTests {
    @Test func viewportFitsContentUnderCap() {
        #expect(PopoverSizing.viewport(content: 200, chrome: 80) == 200)
    }

    @Test func viewportShrinksPastCap() {
        #expect(PopoverSizing.viewport(content: 900, chrome: 80) == 520)
        #expect(PopoverSizing.viewport(content: 900, chrome: 700) == 0)
    }

    @Test func popoverHeightClampsAndRoundsUp() {
        #expect(PopoverSizing.popoverHeight(312.2) == 313)
        #expect(PopoverSizing.popoverHeight(812) == 600)
        #expect(PopoverSizing.popoverHeight(0) == 1)
    }
}
