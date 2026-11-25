import AppKit
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionCompactSizingTests {
    @Test func shortCaptionsDoNotReserveHistorySpace() {
        #expect(FloatingCaptionAppearance.compactWindowHeight(contentHeight: 40) == 112)
        #expect(FloatingCaptionAppearance.compactWindowHeight(contentHeight: 0) == 90)
    }

    @Test func longCaptionsHaveABoundedScrollableViewport() {
        #expect(FloatingCaptionAppearance.compactWindowHeight(contentHeight: 2_000) == 420)
        #expect(FloatingCaptionAppearance.compactWindowHeight(contentHeight: 40) == 112)
        #expect(FloatingCaptionAppearance.compactWindowHeight(contentHeight: .nan) == 90)
    }

    @Test func oversizedWindowShrinksWithoutMovingItsBottomEdgeOrChangingWidth() {
        let frame = NSRect(x: 500, y: 80, width: 720, height: 1_300)
        let fitted = FloatingCaptionAppearance.fittedWindowFrame(frame,
            currentContentHeight: 1_300, targetContentHeight: 180)
        #expect(fitted == NSRect(x: 500, y: 80, width: 720, height: 180))
    }

    @Test func resizingPreservesWindowChrome() {
        let frame = NSRect(x: 500, y: 80, width: 720, height: 200)
        let fitted = FloatingCaptionAppearance.fittedWindowFrame(frame,
            currentContentHeight: 180, targetContentHeight: 250)
        #expect(fitted == NSRect(x: 500, y: 80, width: 720, height: 270))
    }
}
