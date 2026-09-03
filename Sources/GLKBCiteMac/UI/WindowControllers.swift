import AppKit
import GLKBCiteCore
import SwiftUI

@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    private var panel: NSPanel!

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "GLKB Cite"
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 500, height: 420)
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: ResultPanelView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        )
    }

    func show(anchor: ScreenRect?) {
        let desiredSize = panel.frame.size
        panel.setFrameOrigin(
            PanelPlacement.origin(
                size: desiredSize,
                anchor: anchor.map(CGRect.init),
                fallbackPoint: NSEvent.mouseLocation
            )
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if coordinator?.phase == .loading {
            coordinator?.cancelQuery()
        }
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
        let collapsedSize = NSSize(width: 48, height: 48)
        anchorPoint = CGPoint(
            x: event.selection.context.bounds.map { CGFloat($0.x + $0.width + 8) }
                ?? CGFloat(event.pointerLocation.x + 8),
            y: event.selection.context.bounds.map { CGFloat($0.y - 4) }
                ?? CGFloat(event.pointerLocation.y + 8)
        )

        let newPanel = NSPanel(
            contentRect: NSRect(origin: anchorPoint, size: collapsedSize),
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
        constrainToVisibleScreen()
        newPanel.orderFrontRegardless()

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

    private func constrainToVisibleScreen() {
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - panel.frame.width - 6)
        origin.y = min(max(origin.y, visible.minY + 6), visible.maxY - panel.frame.height - 6)
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    private var window: NSWindow!

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up GLKB Cite"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView().environmentObject(coordinator)
        )
        window.center()
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 570),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GLKB Cite Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 500)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .frame(minWidth: 520, minHeight: 500)
        )
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private enum PanelPlacement {
    static func origin(size: NSSize, anchor: CGRect?, fallbackPoint: CGPoint) -> CGPoint {
        let anchorRect = anchor ?? CGRect(origin: fallbackPoint, size: .zero)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(fallbackPoint) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return fallbackPoint }

        var x = anchorRect.midX - size.width / 2
        var y = anchorRect.minY - size.height - 10
        if y < visible.minY {
            y = anchorRect.maxY + 10
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
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
