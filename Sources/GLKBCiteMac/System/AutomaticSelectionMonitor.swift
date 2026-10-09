import AppKit
import Foundation
import GLKBCiteCore

public struct SystemPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SelectionGesture: Hashable, Sendable {
    public var start: SystemPoint
    public var end: SystemPoint
    public var clickCount: Int
    public var shiftPressed: Bool
    public var observedDrag: Bool

    /// Whether the gesture plausibly created a text selection (drag,
    /// double/triple click, or shift-click) rather than a plain click.
    public var isLikelySelection: Bool {
        let distance = hypot(end.x - start.x, end.y - start.y)
        return observedDrag || distance >= 3 || clickCount >= 2 || shiftPressed
    }

    /// A stricter test used before offering a badge for an app that exposes
    /// no selected text through Accessibility: a real drag or a multi-click,
    /// so an ordinary click (or a shift-click on a list row) never qualifies.
    public var isDeliberateSelection: Bool {
        let distance = hypot(end.x - start.x, end.y - start.y)
        return (observedDrag && distance >= 8) || clickCount >= 2
    }

    @available(*, deprecated, renamed: "isLikelySelection")
    public var isCompatibilityEligible: Bool { isLikelySelection }
}

public enum AutomaticSelectionCandidate: Hashable, Sendable {
    /// The selected text was read through Accessibility and is ready to
    /// search as soon as the badge is clicked.
    case captured(SystemSelection)
    /// A deliberate selection gesture happened in an app that exposes no
    /// selected text through Accessibility (PDF viewers, custom canvases).
    /// Nothing has been read yet; clicking the badge is the explicit request
    /// that allows the guarded temporary-Copy fallback to run.
    case provisional(SelectionSource)
}

public struct AutomaticSelectionEvent: Hashable, Sendable {
    public let candidate: AutomaticSelectionCandidate
    public let pointerLocation: SystemPoint
    public let occurredAt: Date
}

@MainActor
public protocol AutomaticSelectionMonitoring: AnyObject {
    var isEnabled: Bool { get }
    func start(
        handler: @escaping @MainActor @Sendable (AutomaticSelectionEvent) -> Void,
        invalidationHandler: @escaping @MainActor @Sendable () -> Void
    )
    func stop()
}

/// Watches for selection gestures in other apps and offers a badge.
///
/// Only mouse and scroll events are observed continuously. A keyboard
/// monitor — whose sole purpose is to dismiss the badge when the user starts
/// typing — is installed only while a badge is on screen and removed again
/// within seconds, so this process never holds a standing keystroke monitor.
/// Event contents are never read or stored.
@MainActor
public final class AutomaticSelectionMonitor: AutomaticSelectionMonitoring {
    private let selectionProvider: any AsyncSystemSelectionCapturing
    private let provisionalBadgeEnabled: @MainActor () -> Bool
    private let debounceNanoseconds: UInt64
    // Only touched on the main actor; declared unsafe so `deinit` can remove
    // them.
    nonisolated(unsafe) private var mouseMonitor: Any?
    nonisolated(unsafe) private var keyMonitor: Any?
    private var keyMonitorExpiry: Task<Void, Never>?
    nonisolated(unsafe) private var applicationActivationObserver: NSObjectProtocol?
    private var pendingCapture: Task<Void, Never>?
    private var handler: (@MainActor @Sendable (AutomaticSelectionEvent) -> Void)?
    private var invalidationHandler: (@MainActor @Sendable () -> Void)?
    private var mouseDownPoint: CGPoint?
    private var observedDrag = false
    /// Apps observed to expose selected text through Accessibility. For
    /// them "no selected text" means nothing is selected, so no provisional
    /// badge is offered after a drag on empty space.
    private var appsWithAccessibleText = Set<String>()

    /// How long the badge-dismissing keyboard monitor may stay installed
    /// after a badge is offered. Matches the badge's own lifetime.
    private static let keyMonitorLifetime: Duration = .seconds(9)

    /// - Parameter provisionalBadgeEnabled: whether a badge may be offered for
    ///   apps that expose no selected text through Accessibility. Wire this to
    ///   the user's Compatibility Capture consent: clicking such a badge runs
    ///   the temporary-Copy fallback.
    public init(
        selectionProvider: any AsyncSystemSelectionCapturing,
        provisionalBadgeEnabled: @escaping @MainActor () -> Bool = { false },
        debounceMilliseconds: UInt64 = 140
    ) {
        self.selectionProvider = selectionProvider
        self.provisionalBadgeEnabled = provisionalBadgeEnabled
        debounceNanoseconds = debounceMilliseconds * 1_000_000
    }

    deinit {
        // Monitors would otherwise keep delivering events to a freed object.
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
    }

    public var isEnabled: Bool { mouseMonitor != nil }

    public func start(
        handler: @escaping @MainActor @Sendable (AutomaticSelectionEvent) -> Void,
        invalidationHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        stop()
        self.handler = handler
        self.invalidationHandler = invalidationHandler
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        ) { [weak self] event in
            // For global-monitor events `window` is nil, so `locationInWindow`
            // is already in screen coordinates. Read it here, before the actor
            // hop: by the time the Task runs the cursor may have moved on.
            let location = event.locationInWindow
            let kind = event.type
            let clickCount = event.clickCount
            let shift = event.modifierFlags.contains(.shift)
            Task { @MainActor [weak self] in
                self?.receive(kind, at: location, clickCount: clickCount, shiftPressed: shift)
            }
        }
        CaptureDiagnostics.log(
            "monitor: started (mouse monitor installed: \(self.mouseMonitor != nil))"
        )
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pendingCapture?.cancel()
                self?.invalidate()
            }
        }
    }

    public func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        removeKeyMonitor()
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
        applicationActivationObserver = nil
        handler = nil
        invalidationHandler = nil
        mouseDownPoint = nil
        observedDrag = false
    }

    private func receive(
        _ kind: NSEvent.EventType,
        at location: CGPoint,
        clickCount: Int,
        shiftPressed: Bool
    ) {
        switch kind {
        case .leftMouseDown:
            pendingCapture?.cancel()
            invalidate()
            mouseDownPoint = location
            observedDrag = false
        case .leftMouseDragged:
            observedDrag = true
        case .leftMouseUp:
            let end = location
            let start = mouseDownPoint ?? end
            let gesture = SelectionGesture(
                start: SystemPoint(x: start.x, y: start.y),
                end: SystemPoint(x: end.x, y: end.y),
                clickCount: clickCount,
                shiftPressed: shiftPressed,
                observedDrag: observedDrag
            )
            mouseDownPoint = nil
            observedDrag = false
            guard gesture.isLikelySelection else { return }
            CaptureDiagnostics.log("monitor: selection gesture observed, scheduling capture")
            scheduleCapture(pointerLocation: end, gesture: gesture)
        case .scrollWheel, .keyDown:
            pendingCapture?.cancel()
            invalidate()
        default:
            break
        }
    }

    private func scheduleCapture(pointerLocation: CGPoint, gesture: SelectionGesture) {
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()
                // Automatic mode must observe selections passively: no Copy
                // fallback (that would post ⌘C into the frontmost app on every
                // drag), and only a shallow look below the focused element so
                // the walk stays cheap on every gesture. Explicit invocations
                // (hot key, badge click) search more thoroughly.
                let selection = try await selectionProvider.captureSelection(
                    SelectionCaptureOptions(allowCompatibility: false, descendantSearch: .shallow)
                )
                try Task.checkCancellation()
                guard (try? LiteratureInputValidator.normalize(selection.context.selectedText)) != nil else {
                    throw SelectionCaptureError.emptySelection
                }
                if let bundle = selection.context.sourceBundleIdentifier {
                    appsWithAccessibleText.insert(bundle)
                }
                emit(.captured(selection), pointerLocation: pointerLocation)
            } catch let SelectionCaptureError.selectionUnavailable(source)
                where shouldOfferProvisionalBadge(for: source, gesture: gesture) {
                CaptureDiagnostics.log(
                    "monitor: no AX text in \(source.bundleIdentifier ?? "?"); offering provisional badge"
                )
                emit(.provisional(source), pointerLocation: pointerLocation)
            } catch {
                if !(error is CancellationError) {
                    CaptureDiagnostics.log("monitor: capture failed — \(Self.diagnosticCode(for: error))")
                }
                invalidate()
            }
        }
    }

    private static func diagnosticCode(for error: Error) -> String {
        if let captureError = error as? SelectionCaptureError { return captureError.diagnosticCode }
        return String(describing: type(of: error))
    }

    /// Apps where a drag almost never means "select text" (file managers,
    /// system UI), plus GLKB Cite itself.
    private static let provisionalBadgeDenylist: Set<String> = [
        "org.glkb.cite",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systempreferences",
        "com.apple.AppStore",
        "com.apple.launchpad.launcher",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    private func shouldOfferProvisionalBadge(for source: SelectionSource, gesture: SelectionGesture) -> Bool {
        guard provisionalBadgeEnabled() else { return false }
        guard gesture.isDeliberateSelection else { return false }
        if let bundle = source.bundleIdentifier {
            if Self.provisionalBadgeDenylist.contains(bundle) { return false }
            // This app does expose selected text; "none found" means nothing
            // is selected, not that the app cannot tell us.
            if appsWithAccessibleText.contains(bundle) { return false }
        }
        // Dragging across a table, outline, or list selects items, not text.
        if selectionProvider.focusedElementIsItemContainer() { return false }
        // The drag must start and end inside one content area — not on a
        // title bar, control, scrollbar, or across two different views.
        return selectionProvider.gestureLandsInContent(
            from: CGPoint(x: gesture.start.x, y: gesture.start.y),
            to: CGPoint(x: gesture.end.x, y: gesture.end.y)
        )
    }

    private func emit(_ candidate: AutomaticSelectionCandidate, pointerLocation: CGPoint) {
        installKeyMonitor()
        handler?(
            AutomaticSelectionEvent(
                candidate: candidate,
                pointerLocation: SystemPoint(x: pointerLocation.x, y: pointerLocation.y),
                occurredAt: Date()
            )
        )
    }

    /// Dismiss-on-typing. Installed only while a badge is offered; the event
    /// is discarded unread.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pendingCapture?.cancel()
                self?.invalidate()
            }
        }
        keyMonitorExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.keyMonitorLifetime)
            guard !Task.isCancelled else { return }
            self?.removeKeyMonitor()
        }
    }

    private func removeKeyMonitor() {
        keyMonitorExpiry?.cancel()
        keyMonitorExpiry = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func invalidate() {
        removeKeyMonitor()
        invalidationHandler?()
    }
}
