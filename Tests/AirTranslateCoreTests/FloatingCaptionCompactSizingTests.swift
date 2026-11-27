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

    @Test func waitingDoesNotMoveOrResizeThePanel() {
        var placement = FloatingCaptionWindowPlacement()
        let current = NSRect(x: 2200, y: 300, width: 720, height: 180)
        let result = placement.fittedFrame(current: current, currentContentHeight: 180,
            targetContentHeight: 90, visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            minimumSize: NSSize(width: 420, height: 90), hasCaptionText: false)
        #expect(result == current)
    }

    @Test func autoGrowthNearScreenEdgeDoesNotPermanentlyShiftTheAnchor() {
        var placement = FloatingCaptionWindowPlacement()
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let original = NSRect(x: 500, y: 850, width: 720, height: 120)
        let grown = placement.fittedFrame(current: original, currentContentHeight: 120,
            targetContentHeight: 420, visibleFrame: screen,
            minimumSize: NSSize(width: 420, height: 90), hasCaptionText: true)
        #expect(grown.minY < original.minY)
        let shrunk = placement.fittedFrame(current: grown, currentContentHeight: 420,
            targetContentHeight: 120, visibleFrame: screen,
            minimumSize: NSSize(width: 420, height: 90), hasCaptionText: true)
        #expect(shrunk.origin == original.origin)
    }

    @Test func widthChangeWhileWaitingPreservesBottomEdgeAndReflowsCaptions() {
        var placement = FloatingCaptionWindowPlacement()
        let screen = NSRect(x: 1920, y: 0, width: 1440, height: 900)
        let minimum = NSSize(width: 420, height: 90)
        let current = NSRect(x: 2150, y: 12, width: 760, height: 240)
        let resized = placement.fittedFrame(current: current, currentContentHeight: 240,
            targetContentHeight: 90, visibleFrame: screen, minimumSize: minimum,
            hasCaptionText: false, targetWindowWidth: 540)
        #expect(resized == NSRect(x: 2260, y: 12, width: 540, height: 240))

        let fitted = placement.fittedFrame(current: resized, currentContentHeight: 240,
            targetContentHeight: 180, visibleFrame: screen, minimumSize: minimum,
            hasCaptionText: true, targetWindowWidth: 540)
        #expect(fitted.width == resized.width)
        #expect(fitted.midX == resized.midX)
        #expect(fitted.height == 180)
    }

    @Test func manualMoveAcrossDisplaysBecomesTheNewAnchor() {
        var placement = FloatingCaptionWindowPlacement()
        let original = NSRect(x: 500, y: 200, width: 720, height: 120)
        _ = placement.fittedFrame(current: original, currentContentHeight: 120,
            targetContentHeight: 120, visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            minimumSize: NSSize(width: 420, height: 90), hasCaptionText: true)
        let moved = NSRect(x: 2200, y: 150, width: 720, height: 120)
        let resized = placement.fittedFrame(current: moved, currentContentHeight: 120,
            targetContentHeight: 240, visibleFrame: NSRect(x: 1920, y: 0, width: 1440, height: 900),
            minimumSize: NSSize(width: 420, height: 90), hasCaptionText: true)
        #expect(resized.origin == moved.origin)
    }
}
