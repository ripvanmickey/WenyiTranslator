import AppKit
import SwiftUI

struct FloatingCaptionDragSurface: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = DragView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            // AppKit tracks the drag across the desktop's displays. Clamping each
            // update to window.screen traps the panel before it can cross an edge.
            window?.performDrag(with: event)
        }
    }
}
