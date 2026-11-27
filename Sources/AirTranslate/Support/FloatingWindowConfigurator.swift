import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
    let preferredContentHeight: CGFloat
    let preferredWindowWidth: CGFloat
    let minimumWindowSize: NSSize
    let keepsAboveOtherWindows: Bool
    let hasCaptionText: Bool
    let onWidthChanged: (CGFloat) -> Void

    final class Coordinator {
        var revision = 0
        weak var window: NSWindow?
        var placement = FloatingCaptionWindowPlacement()
        var appliedWidth: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context _: Context) -> ResizeObserver {
        ResizeObserver()
    }

    func updateNSView(_ view: ResizeObserver, context: Context) {
        view.onWidthChanged = onWidthChanged
        let coordinator = context.coordinator
        coordinator.revision += 1
        let revision = coordinator.revision
        DispatchQueue.main.async {
            guard coordinator.revision == revision, let window = view.window else { return }
            if coordinator.window !== window {
                coordinator.window = window
                coordinator.placement = FloatingCaptionWindowPlacement()
                coordinator.appliedWidth = nil
            }

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

            let widthChanged = coordinator.appliedWidth != preferredWindowWidth
            // Waiting captions keep their frame unless the user changes the width.
            guard !window.inLiveResize, hasCaptionText || widthChanged else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }
            let maximumSize = FloatingCaptionWindowController.maximumWindowSize(for: screen)
            let safeMinimumSize = NSSize(
                width: max(FloatingCaptionWindowController.minimumWindowSize.width, minimumWindowSize.width),
                height: max(FloatingCaptionWindowController.minimumWindowSize.height, minimumWindowSize.height)
            )
            let targetContentHeight = min(max(preferredContentHeight, safeMinimumSize.height), maximumSize.height)
            let targetWindowWidth = min(max(preferredWindowWidth, safeMinimumSize.width), maximumSize.width)
            let current = window.frame
            let target = coordinator.placement.fittedFrame(current: current,
                currentContentHeight: window.contentLayoutRect.height,
                targetContentHeight: targetContentHeight, visibleFrame: screen.visibleFrame,
                minimumSize: safeMinimumSize, hasCaptionText: hasCaptionText,
                targetWindowWidth: targetWindowWidth)
            coordinator.appliedWidth = preferredWindowWidth
            window.maxSize = maximumSize
            window.minSize = safeMinimumSize
            if !NSEqualRects(target, window.frame) { window.setFrame(target, display: true) }
        }
    }

    final class ResizeObserver: NSView {
        var onWidthChanged: ((CGFloat) -> Void)?
        private var startingWidth: CGFloat?

        override func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            startingWidth = window?.frame.width
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            defer { startingWidth = nil }
            guard let startingWidth, let width = window?.frame.width,
                  abs(width - startingWidth) >= 0.5 else { return }
            onWidthChanged?(width)
        }
    }
}
