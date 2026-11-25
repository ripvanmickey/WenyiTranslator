import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
    let preferredContentHeight: CGFloat
    let minimumWindowSize: NSSize
    let keepsAboveOtherWindows: Bool
    let hasCaptionText: Bool

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.identifier = NSUserInterfaceItemIdentifier(AirTranslateWindowID.floatingCaptions)
            window.level = keepsAboveOtherWindows ? .floating : .normal
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = !hasCaptionText

            let maximumSize = FloatingCaptionWindowController.maximumWindowSize(for: window.screen ?? NSScreen.main)
            window.maxSize = maximumSize
            let safeMinimumSize = NSSize(
                width: max(FloatingCaptionWindowController.minimumWindowSize.width, minimumWindowSize.width),
                height: max(FloatingCaptionWindowController.minimumWindowSize.height, minimumWindowSize.height)
            )
            let targetContentHeight = min(max(preferredContentHeight, safeMinimumSize.height), maximumSize.height)
            window.minSize = safeMinimumSize
            if abs(window.contentLayoutRect.height - targetContentHeight) > 1 {
                window.setFrame(FloatingCaptionAppearance.fittedWindowFrame(window.frame,
                    currentContentHeight: window.contentLayoutRect.height,
                    targetContentHeight: targetContentHeight), display: true)
            }
            keepWindowVisible(window)
        }
    }

    private func keepWindowVisible(_ window: NSWindow) {
        guard window.isVisible else { return }
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        let frame = FloatingCaptionWindowController.clampedFrame(
            window.frame,
            within: visibleFrame,
            minimumSize: minimumWindowSize
        )

        if !NSEqualRects(frame, window.frame) {
            window.setFrame(frame, display: true)
        }
    }
}
