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

@MainActor
public final class AutomaticSelectionMonitor: AutomaticSelectionMonitoring {
    private let selectionProvider: any AsyncSystemSelectionCapturing
    private let provisionalBadgeEnabled: @MainActor () -> Bool
    private let debounceNanoseconds: UInt64
    private var eventMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var pendingCapture: Task<Void, Never>?
    private var handler: (@MainActor @Sendable (AutomaticSelectionEvent) -> Void)?
    private var invalidationHandler: (@MainActor @Sendable () -> Void)?
    private var mouseDownPoint: CGPoint?
    private var observedDrag = false
    /// Apps observed to expose selected text through Accessibility. For
    /// them "no selected text" means nothing is selected, so no provisional
    /// badge is offered after a drag on empty space.
    private var appsWithAccessibleText = Set<String>()

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

    public var isEnabled: Bool { eventMonitor != nil }

    public func start(
        handler: @escaping @MainActor @Sendable (AutomaticSelectionEvent) -> Void,
        invalidationHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        stop()
        self.handler = handler
        self.invalidationHandler = invalidationHandler
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .scrollWheel]
        ) { [weak self] event in
            // For global-monitor events `window` is nil, so `locationInWindow`
            // is already in screen coordinates. Read it here, before the actor
            // hop: by the time the Task runs the cursor may have moved on.
            let location = event.locationInWindow
            Task { @MainActor [weak self] in self?.receive(event, at: location) }
        }
        CaptureDiagnostics.log(
            "monitor: started (event monitor installed: \(eventMonitor != nil))"
        )
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pendingCapture?.cancel()
                self?.invalidationHandler?()
            }
        }
    }

    public func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
        applicationActivationObserver = nil
        handler = nil
        invalidationHandler = nil
        mouseDownPoint = nil
        observedDrag = false
    }

    private func receive(_ event: NSEvent, at location: CGPoint) {
        switch event.type {
        case .leftMouseDown:
            pendingCapture?.cancel()
            invalidationHandler?()
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
                clickCount: event.clickCount,
                shiftPressed: event.modifierFlags.contains(.shift),
                observedDrag: observedDrag
            )
            mouseDownPoint = nil
            observedDrag = false
            guard gesture.isLikelySelection else { return }
            CaptureDiagnostics.log("monitor: selection gesture observed, scheduling capture")
            // Automatic mode must observe selections passively. The
            // clipboard-compatibility path posts a synthetic ⌘C into the
            // frontmost app, which would fire on ordinary drag gestures and
            // contradict the "observes selection gestures locally" promise —
            // so it is reserved for explicit invocations (hot key, Services).
            scheduleCapture(pointerLocation: end, gesture: gesture)
        case .keyDown, .scrollWheel:
            pendingCapture?.cancel()
            invalidationHandler?()
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
                let selection = try await selectionProvider.captureSelection(
                    allowCompatibility: false
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
                    CaptureDiagnostics.log("monitor: capture failed — \(error)")
                }
                invalidationHandler?()
            }
        }
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
        // The drag must start and end inside one content element — not on a
        // title bar, control, scrollbar, or across two different views.
        return selectionProvider.gestureLandsInContent(
            from: CGPoint(x: gesture.start.x, y: gesture.start.y),
            to: CGPoint(x: gesture.end.x, y: gesture.end.y)
        )
    }

    private func emit(_ candidate: AutomaticSelectionCandidate, pointerLocation: CGPoint) {
        handler?(
            AutomaticSelectionEvent(
                candidate: candidate,
                pointerLocation: SystemPoint(x: pointerLocation.x, y: pointerLocation.y),
                occurredAt: Date()
            )
        )
    }
}
