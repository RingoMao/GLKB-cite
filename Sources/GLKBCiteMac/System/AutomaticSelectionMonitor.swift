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

    public var isCompatibilityEligible: Bool {
        let distance = hypot(end.x - start.x, end.y - start.y)
        return observedDrag || distance >= 3 || clickCount >= 2 || shiftPressed
    }
}

public struct AutomaticSelectionEvent: Hashable, Sendable {
    public let selection: SystemSelection
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
    private struct Fingerprint: Hashable {
        let text: String
        let processIdentifier: pid_t
        let method: SelectionCaptureMethod
    }

    private let selectionProvider: any AsyncSystemSelectionCapturing
    private let debounceNanoseconds: UInt64
    private let repeatedSelectionInterval: TimeInterval
    private var eventMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var pendingCapture: Task<Void, Never>?
    private var handler: (@MainActor @Sendable (AutomaticSelectionEvent) -> Void)?
    private var invalidationHandler: (@MainActor @Sendable () -> Void)?
    private var mouseDownPoint: CGPoint?
    private var observedDrag = false
    private var lastFingerprint: Fingerprint?
    private var lastEmissionDate: Date?

    public init(
        selectionProvider: any AsyncSystemSelectionCapturing,
        debounceMilliseconds: UInt64 = 140,
        repeatedSelectionInterval: TimeInterval = 1.25
    ) {
        self.selectionProvider = selectionProvider
        debounceNanoseconds = debounceMilliseconds * 1_000_000
        self.repeatedSelectionInterval = max(0, repeatedSelectionInterval)
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
            Task { @MainActor [weak self] in self?.receive(event) }
        }
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
        lastFingerprint = nil
        lastEmissionDate = nil
    }

    private func receive(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pendingCapture?.cancel()
            invalidationHandler?()
            mouseDownPoint = NSEvent.mouseLocation
            observedDrag = false
        case .leftMouseDragged:
            observedDrag = true
        case .leftMouseUp:
            let end = NSEvent.mouseLocation
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
            scheduleCapture(pointerLocation: end, allowCompatibility: gesture.isCompatibilityEligible)
        case .keyDown, .scrollWheel:
            pendingCapture?.cancel()
            invalidationHandler?()
        default:
            break
        }
    }

    private func scheduleCapture(pointerLocation: CGPoint, allowCompatibility: Bool) {
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()
                let selection = try await selectionProvider.captureSelection(
                    allowCompatibility: allowCompatibility
                )
                try Task.checkCancellation()
                guard (try? LiteratureInputValidator.normalize(selection.context.selectedText)) != nil else {
                    throw SelectionCaptureError.emptySelection
                }
                emit(selection, pointerLocation: pointerLocation)
            } catch {
                lastFingerprint = nil
                lastEmissionDate = nil
                invalidationHandler?()
            }
        }
    }

    private func emit(_ selection: SystemSelection, pointerLocation: CGPoint) {
        let fingerprint = Fingerprint(
            text: selection.context.selectedText,
            processIdentifier: selection.sourceProcessIdentifier,
            method: selection.context.captureMethod
        )
        let now = Date()
        if fingerprint == lastFingerprint,
           let lastEmissionDate,
           now.timeIntervalSince(lastEmissionDate) < repeatedSelectionInterval {
            return
        }
        lastFingerprint = fingerprint
        lastEmissionDate = now
        handler?(
            AutomaticSelectionEvent(
                selection: selection,
                pointerLocation: SystemPoint(x: pointerLocation.x, y: pointerLocation.y),
                occurredAt: now
            )
        )
    }
}
