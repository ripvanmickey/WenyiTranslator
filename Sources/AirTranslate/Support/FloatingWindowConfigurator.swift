import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
    let preferredContentHeight: CGFloat
    let minimumWindowSize: NSSize
    let keepsAboveOtherWindows: Bool
    let hasCaptionText: Bool

    final class Coordinator {
        var revision = 0
        weak var window: NSWindow?
        var placement = FloatingCaptionWindowPlacement()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.revision += 1
        let revision = coordinator.revision
        DispatchQueue.main.async {
            guard coordinator.revision == revision, let window = view.window else { return }
            if coordinator.window !== window {
                coordinator.window = window
                coordinator.placement = FloatingCaptionWindowPlacement()
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

            // Empty/waiting captions must not move or resize the invisible panel.
            guard hasCaptionText else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }
            let maximumSize = FloatingCaptionWindowController.maximumWindowSize(for: screen)
            let safeMinimumSize = NSSize(
                width: max(FloatingCaptionWindowController.minimumWindowSize.width, minimumWindowSize.width),
                height: max(FloatingCaptionWindowController.minimumWindowSize.height, minimumWindowSize.height)
            )
            let targetContentHeight = min(max(preferredContentHeight, safeMinimumSize.height), maximumSize.height)
            let current = window.frame
            let target = coordinator.placement.fittedFrame(current: current,
                currentContentHeight: window.contentLayoutRect.height,
                targetContentHeight: targetContentHeight, visibleFrame: screen.visibleFrame,
                minimumSize: safeMinimumSize, hasCaptionText: hasCaptionText)
            window.maxSize = maximumSize
            window.minSize = safeMinimumSize
            if !NSEqualRects(target, window.frame) { window.setFrame(target, display: true) }
        }
    }
}
