import AppKit
import GLKBCiteCore
import SwiftUI

/// Borderless panel that can still become key so buttons, scrolling, and
/// text selection work, and that closes on Escape.
private final class FloatingKeyablePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Hosts the results panel.
///
/// The first result stays centered on the pointer's display as it loads.
/// Later openings use the selection's display. Dragging takes over placement.
@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    private var panel: FloatingKeyablePanel!
    /// The top-left corner the panel is pinned to while visible.
    private var pinnedTopLeft: CGPoint?
    private var isRepositioning = false
    private var hasPresented = false
    private var centerOnResize = false
    private var placementScreen: NSScreen?

    private static let screenMargin: CGFloat = 16

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        panel = FloatingKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }

        let hosting = NSHostingController(
            rootView: ResultPanelView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
    }

    func show(anchor: ScreenRect?) {
        if !panel.isVisible {
            centerOnResize = !hasPresented
            hasPresented = true
            placementScreen = Self.targetScreen(for: centerOnResize ? nil : anchor.map(CGRect.init))
        }
        let screen = placementScreen ?? panel.screen
        if let visible = screen?.visibleFrame {
            coordinator?.limitResultPanelHeight(toAvailable: visible.height - 2 * Self.screenMargin)
        }
        panel.layoutIfNeeded()
        if !panel.isVisible {
            if let visible = screen?.visibleFrame {
                pin(topLeft: CGPoint(x: visible.maxX - Self.screenMargin - panel.frame.width,
                                     y: visible.maxY - Self.screenMargin))
            }
        }
        panel.orderFrontRegardless()
        // Key status is what makes Escape close the panel and lets its
        // buttons respond to a first click; the editor the user was in keeps
        // its own focus state and regains key status when the panel closes.
        panel.makeKey()
        coordinator?.setResultPanelVisible(true)
    }

    func hide() {
        if coordinator?.phase == .loading {
            coordinator?.cancelQuery()
        }
        panel.orderOut(nil)
        pinnedTopLeft = nil
        coordinator?.setResultPanelVisible(false)
    }

    // MARK: Placement

    private func pin(topLeft: CGPoint) {
        guard let visible = (placementScreen ?? panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let origin = Self.constrainedOrigin(topLeft: topLeft, size: panel.frame.size,
                                            visible: visible, centered: centerOnResize)
        pinnedTopLeft = CGPoint(x: origin.x, y: origin.y + panel.frame.height)
        isRepositioning = true
        panel.setFrameOrigin(origin)
        isRepositioning = false
    }

    static func constrainedOrigin(topLeft: CGPoint, size: CGSize, visible: CGRect, centered: Bool) -> CGPoint {
        let x = centered ? visible.midX - size.width / 2 : topLeft.x
        let y = centered ? visible.midY - size.height / 2 : topLeft.y - size.height
        let marginX = min(screenMargin, max(0, (visible.width - size.width) / 2))
        let marginY = min(screenMargin, max(0, (visible.height - size.height) / 2))
        return CGPoint(
            x: max(visible.minX + marginX, min(x, visible.maxX - marginX - size.width)),
            y: max(visible.minY + marginY, min(y, visible.maxY - marginY - size.height))
        )
    }

    /// The display the selection was made on, else the one under the pointer.
    private static func targetScreen(for anchor: CGRect?) -> NSScreen? {
        if let anchor, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return screen
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
    }

    // MARK: NSWindowDelegate

    /// SwiftUI resizes the panel as its content changes; keep the top edge
    /// where it was so the panel grows and shrinks downward.
    func windowDidResize(_ notification: Notification) {
        guard let pinnedTopLeft else { return }
        pin(topLeft: pinnedTopLeft)
    }

    /// Any move we did not make ourselves is the user dragging the panel:
    /// adopt that position for the rest of this visibility session.
    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning, panel.isVisible else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            centerOnResize = false
            placementScreen = panel.screen
        }
        guard !centerOnResize else { return }
        pinnedTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    /// Current on-screen frame, or nil while hidden.
    var frame: NSRect? { panel.isVisible ? panel.frame : nil }
}

/// The 460pt "Cite" modal from the mockup, presented as its own floating
/// panel centred over the results panel (which is only 380pt wide).
@MainActor
final class CitePanelController {
    private weak var coordinator: AppCoordinator?
    private var panel: FloatingKeyablePanel!

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        panel = FloatingKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak coordinator] in coordinator?.dismissCite() }

        let hosting = NSHostingController(
            rootView: CitePanelView()
                .environmentObject(coordinator)
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
    }

    func show(over anchor: NSRect?) {
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let reference = anchor ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        var origin = CGPoint(x: reference.midX - size.width / 2, y: reference.midY - size.height / 2)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(reference) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@MainActor
final class SelectionBadgePanelController {
    private weak var coordinator: AppCoordinator?
    private var panel: NSPanel?
    private var anchorPoint = CGPoint.zero
    private var dismissTask: Task<Void, Never>?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show(event: AutomaticSelectionEvent) {
        dismiss()
        // The badge always sits beside the point where the mouse button was
        // released. Selection bounds are not used for placement: apps report
        // them inconsistently, and for multi-line selections the rectangle's
        // edge can be a long way from where the user's attention (and cursor)
        // actually is.
        let pointer = CGPoint(x: event.pointerLocation.x, y: event.pointerLocation.y)
        let panelSize = NSSize(width: SelectionBadgeView.panelSize, height: SelectionBadgeView.panelSize)
        let tile = SelectionBadgeView.tileSize
        let margin = SelectionBadgeView.margin
        let screen = Self.screen(containing: pointer)
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: panelSize)

        // Preferred spot: up and to the right of the arrow cursor, which keeps
        // the badge clear of both the cursor glyph and the text just selected.
        var tileOrigin = CGPoint(x: pointer.x + 12, y: pointer.y + 10)
        var placement = "up-right"
        if tileOrigin.x + tile > visible.maxX - 8 {
            tileOrigin.x = pointer.x - 12 - tile
            placement = "up-left"
        }
        if tileOrigin.y + tile > visible.maxY - 8 {
            tileOrigin.y = pointer.y - 26 - tile
            placement = placement.replacingOccurrences(of: "up", with: "down")
        }
        anchorPoint = CGPoint(x: tileOrigin.x - margin, y: tileOrigin.y - margin)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: anchorPoint, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        newPanel.contentViewController = NSHostingController(
            rootView: SelectionBadgeView(
                onFindCitations: { [weak coordinator] in
                    coordinator?.handleAutomaticAction()
                }
            )
        )
        panel = newPanel
        constrainToVisibleScreen(preferring: screen)
        newPanel.orderFrontRegardless()
        CaptureDiagnostics.log(
            "badge: shown \(placement) of pointer"
        )

        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// The display the pointer is on. `NSMouseInRect` (not `CGRect.contains`)
    /// treats a display's top edge as inside — `NSEvent.mouseLocation` reports
    /// exactly `frame.maxY` when the cursor is pinned to the top pixel row. If
    /// no display claims the point, use the nearest one rather than
    /// `NSScreen.main`, which can be an unrelated monitor.
    private static func screen(containing point: CGPoint) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return hit
        }
        return NSScreen.screens.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        } ?? NSScreen.main
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func constrainToVisibleScreen(preferring preferred: NSScreen?) {
        guard let panel else { return }
        let screen = preferred
            ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        // Keep the visible tile (not the transparent shadow margin) on screen.
        let margin = SelectionBadgeView.margin
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, visible.minX + 6 - margin), visible.maxX - panel.frame.width - 6 + margin)
        origin.y = min(max(origin.y, visible.minY + 6 - margin), visible.maxY - panel.frame.height - 6 + margin)
        panel.setFrameOrigin(origin)
    }
}


/// An accessory (menu-bar) app that activated itself to show a window keeps
/// keyboard focus after that window closes, with nowhere for input to go.
/// Deactivating lets macOS return focus to the previously active app.
@MainActor
private func deactivateIfNoWindowsRemain() {
    let stillVisible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
    if !stillVisible { NSApp.deactivate() }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    private var window: NSWindow!

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up GLKB Cite"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        )
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        // Run after the window has actually gone away.
        Task { @MainActor in deactivateIfNoWindowsRemain() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}

@MainActor
final class CiteSettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!

    init(coordinator: AppCoordinator) {
        super.init()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GLKB Cite Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 440)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .frame(minWidth: 600, minHeight: 440)
        )
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        // Run after the window has actually gone away.
        Task { @MainActor in deactivateIfNoWindowsRemain() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private extension CGRect {
    init(_ screenRect: ScreenRect) {
        self.init(
            x: screenRect.x,
            y: screenRect.y,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}
