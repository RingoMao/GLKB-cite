import AppKit
import SwiftUI

/// Makes a region of a borderless panel behave like a title bar: pressing
/// and dragging anywhere on it moves the window, exactly as with a standard
/// macOS window. Place it as the `.background` of a header row, keeping
/// interactive controls (such as the close button) outside that row so they
/// still receive their own clicks.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        /// Start a drag on the very first click, even when the panel is not
        /// the key window.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
