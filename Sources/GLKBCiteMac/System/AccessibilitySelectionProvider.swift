import AppKit
import ApplicationServices
import Foundation
import GLKBCiteCore

public struct SelectionSource: Hashable, Sendable {
    public let processIdentifier: pid_t
    public let applicationName: String?
    public let bundleIdentifier: String?
}

public struct SystemSelection: Hashable, Sendable {
    public let context: SelectionContext
    public let sourceProcessIdentifier: pid_t

    public init(context: SelectionContext, sourceProcessIdentifier: pid_t) {
        self.context = context
        self.sourceProcessIdentifier = sourceProcessIdentifier
    }
}

public enum SelectionCaptureError: Error, LocalizedError {
    case accessibilityPermissionRequired
    case focusedElementUnavailable
    case secureField
    case selectionUnavailable(source: SelectionSource)
    case emptySelection
    case staleSelection
    case accessibilityFailure(operation: String, code: AXError)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Allow GLKB Cite in System Settings > Privacy & Security > Accessibility."
        case .focusedElementUnavailable:
            "The focused application did not expose a text element."
        case .secureField:
            "GLKB Cite never reads text from password or secure fields."
        case .selectionUnavailable:
            "The focused application did not expose selected text. Enable Compatibility Capture or use the GLKB Cite Service."
        case .emptySelection:
            "Select one scientific sentence before using GLKB Cite."
        case .staleSelection:
            "The original selection changed. Select it again before finding citations."
        case let .accessibilityFailure(operation, code):
            "macOS Accessibility could not \(operation) (error \(code.rawValue))."
        }
    }
}

@MainActor
public protocol AccessibilitySelectionCapturing: AnyObject {
    func captureSelection() throws -> SystemSelection
    /// Whether the focused element is a table/outline/list whose "selection"
    /// is items rather than text. Used to avoid offering a badge after a drag
    /// that selected files or rows.
    func focusedElementIsItemContainer() -> Bool
    /// Whether a drag from `start` to `end` (AppKit screen coordinates) began
    /// and ended inside the same content element (document, page, image, web
    /// area…) rather than on window chrome, a control, or two different views.
    func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool
}

public extension AccessibilitySelectionCapturing {
    func focusedElementIsItemContainer() -> Bool { false }
    func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool { true }
}

@MainActor
public protocol AsyncSystemSelectionCapturing: AnyObject {
    func captureSelection(allowCompatibility: Bool) async throws -> SystemSelection
    /// Like `captureSelection(allowCompatibility:)`, but refuses to run the
    /// compatibility (Copy) fallback unless the selection's source process is
    /// `expectedProcess`, so a badge offered for one app can never copy from
    /// another app that became frontmost in the meantime.
    func captureSelection(allowCompatibility: Bool, expectedProcess: pid_t?) async throws -> SystemSelection
    func isStillValid(_ selection: SystemSelection) async -> Bool
    func focusedElementIsItemContainer() -> Bool
    func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool
}

public extension AsyncSystemSelectionCapturing {
    func captureSelection(allowCompatibility: Bool, expectedProcess: pid_t?) async throws -> SystemSelection {
        let selection = try await captureSelection(allowCompatibility: allowCompatibility)
        if let expectedProcess, selection.sourceProcessIdentifier != expectedProcess {
            throw SelectionCaptureError.staleSelection
        }
        return selection
    }
    func focusedElementIsItemContainer() -> Bool { false }
    func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool { true }
}

@MainActor
public final class AccessibilitySelectionProvider: AccessibilitySelectionCapturing {
    private let permissionManager: any AccessibilityPermissionManaging

    public convenience init() {
        self.init(permissionManager: AccessibilityPermissionManager())
    }

    public init(permissionManager: any AccessibilityPermissionManaging) {
        self.permissionManager = permissionManager
    }

    public func captureSelection() throws -> SystemSelection {
        guard permissionManager.isTrusted else {
            throw SelectionCaptureError.accessibilityPermissionRequired
        }

        // Bound every accessibility round trip for this capture. Setting the
        // timeout on the system-wide element applies it process-wide, so the
        // focused-element read, the secure-field walk, and the ancestor walk
        // are all protected against an unresponsive frontmost app.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)

        let element = try focusedElement()
        guard !isSecure(element) else { throw SelectionCaptureError.secureField }
        let source = try source(for: element)

        guard let resolved = resolveSelection(startingAt: element) else {
            CaptureDiagnostics.log(
                "ax: no selected text — app=\(source.bundleIdentifier ?? "?") "
                    + "focusedRole=\(role(of: element))"
            )
            throw SelectionCaptureError.selectionUnavailable(source: source)
        }
        // The text may have come from an ancestor or descendant of the focused
        // element; enforce the secure-field policy on that element as well.
        guard !isSecure(resolved.element) else { throw SelectionCaptureError.secureField }
        let capturedText = resolved.text
        CaptureDiagnostics.log(
            "ax: found selection — app=\(source.bundleIdentifier ?? "?") "
                + "focusedRole=\(role(of: element)) "
                + "holderRole=\(role(of: resolved.element)) "
                + "via=\(resolved.strategy) chars=\(capturedText.count)"
        )

        let rawBounds: CGRect?
        if let markerRange = resolved.textMarkerRange {
            rawBounds = bounds(forTextMarkerRange: markerRange, in: resolved.element)
        } else {
            rawBounds = selectedTextRange(from: resolved.element)
                .flatMap { selectionBounds(for: $0, in: resolved.element) }
        }
        let bounds = rawBounds.map(appKitScreenRect(from:))
        let context = SelectionContext(
            selectedText: capturedText,
            sourceApplicationName: source.applicationName,
            sourceBundleIdentifier: source.bundleIdentifier,
            bounds: bounds.map {
                ScreenRect(
                    x: Double($0.origin.x), y: Double($0.origin.y),
                    width: Double($0.size.width), height: Double($0.size.height)
                )
            },
            isEditable: false,
            captureMethod: .accessibility
        )
        return SystemSelection(context: context, sourceProcessIdentifier: source.processIdentifier)
    }

    public func focusedElementIsItemContainer() -> Bool {
        guard permissionManager.isTrusted, let element = try? focusedElement() else { return false }
        if Self.itemContainerRoles.contains(role(of: element)) { return true }
        var rawNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &rawNames) == .success,
              let names = rawNames as? [String] else { return false }
        return names.contains(kAXSelectedRowsAttribute) || names.contains(kAXSelectedCellsAttribute)
    }

    private static let itemContainerRoles: Set<String> = [
        kAXTableRole, kAXOutlineRole, kAXListRole, kAXBrowserRole, kAXGridRole, kAXColumnRole,
    ]

    public func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool {
        guard permissionManager.isTrusted,
              let startElement = element(atAppKitPoint: start),
              let endElement = element(atAppKitPoint: end),
              CFEqual(startElement, endElement)
        else { return false }
        return Self.contentRoles.contains(role(of: startElement))
    }

    /// Roles that plausibly display selectable document content. Window
    /// chrome, controls, menus, scrollbars, and item containers are excluded.
    private static let contentRoles: Set<String> = [
        kAXScrollAreaRole, kAXGroupRole, kAXImageRole, "AXWebArea", kAXTextAreaRole,
        kAXTextFieldRole, kAXStaticTextRole, kAXLayoutAreaRole, kAXLayoutItemRole,
        kAXUnknownRole, "AXPage", "AXDocument", "AXCanvas",
    ]

    private func element(atAppKitPoint point: CGPoint) -> AXUIElement? {
        // Accessibility hit-testing uses top-left-origin coordinates relative
        // to the primary display.
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        var raw: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(primaryHeight - point.y), &raw
        )
        guard result == .success, let raw else { return nil }
        return raw
    }

    private func focusedElement() throws -> AXUIElement {
        let systemWideElement = AXUIElementCreateSystemWide()
        var rawElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWideElement, kAXFocusedUIElementAttribute as CFString, &rawElement
        )
        switch error {
        case .success:
            guard let rawElement, CFGetTypeID(rawElement) == AXUIElementGetTypeID() else {
                throw SelectionCaptureError.focusedElementUnavailable
            }
            return unsafeDowncast(rawElement as AnyObject, to: AXUIElement.self)
        case .noValue, .attributeUnsupported:
            throw SelectionCaptureError.focusedElementUnavailable
        default:
            throw SelectionCaptureError.accessibilityFailure(
                operation: "read the focused element", code: error
            )
        }
    }

    private func source(for element: AXUIElement) throws -> SelectionSource {
        var pid: pid_t = 0
        let error = AXUIElementGetPid(element, &pid)
        guard error == .success, pid > 0 else {
            throw SelectionCaptureError.accessibilityFailure(
                operation: "identify the source application", code: error
            )
        }
        let app = NSRunningApplication(processIdentifier: pid)
        return SelectionSource(
            processIdentifier: pid,
            applicationName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier
        )
    }

    /// Reads `AXSelectedText` from one element, treating an unsupported
    /// attribute and an empty value alike as "nothing here".
    private func selectedTextValue(of element: AXUIElement) -> String? {
        var rawText: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &rawText
        ) == .success,
            let text = rawText as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// Finds the element that actually holds the selection.
    ///
    /// The system-wide focused element is often a container that does not
    /// expose `AXSelectedText` itself — browsers focus a web area or scroll
    /// area whose selection lives on a descendant, and some apps keep it on
    /// an ancestor. So the focused element is only the starting point: this
    /// walks up the ancestor chain and then breadth-first down the focused
    /// window, both bounded so a large document cannot stall the capture.
    private struct ResolvedSelection {
        let element: AXUIElement
        let text: String
        let strategy: String
        /// Opaque `AXTextMarkerRange` when the selection came from a WebKit
        /// web area; needed to ask that element for the selection bounds.
        let textMarkerRange: CFTypeRef?
    }

    private func resolveSelection(startingAt focused: AXUIElement) -> ResolvedSelection? {
        if let hit = selection(of: focused, strategy: "focused") { return hit }

        var ancestor = parent(of: focused)
        for depth in 1...Self.ancestorLimit {
            guard let element = ancestor else { break }
            if let hit = selection(of: element, strategy: "ancestor-\(depth)") { return hit }
            ancestor = parent(of: element)
        }

        let root = topLevelElement(of: focused) ?? focused
        return searchDescendants(of: root)
    }

    /// Checks one element for a selection, using whichever API its role
    /// supports: plain `AXSelectedText` for native text, or WebKit's
    /// text-marker range for a web area (Safari and WebKit views never expose
    /// page selections through `AXSelectedText`).
    private func selection(of element: AXUIElement, strategy: String) -> ResolvedSelection? {
        if let text = selectedTextValue(of: element) {
            return ResolvedSelection(element: element, text: text, strategy: strategy, textMarkerRange: nil)
        }
        if role(of: element) == Self.webAreaRole, let web = webAreaSelection(of: element) {
            return ResolvedSelection(
                element: element, text: web.text, strategy: "\(strategy)/webarea",
                textMarkerRange: web.markerRange
            )
        }
        return nil
    }

    private func webAreaSelection(of element: AXUIElement) -> (text: String, markerRange: CFTypeRef)? {
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, Self.selectedTextMarkerRangeAttribute as CFString, &rawRange
        ) == .success, let rawRange else { return nil }

        var rawString: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, Self.stringForTextMarkerRangeAttribute as CFString, rawRange, &rawString
        ) == .success,
            let text = rawString as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return (text, rawRange)
    }

    private func bounds(forTextMarkerRange range: CFTypeRef, in element: AXUIElement) -> CGRect? {
        var rawBounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, Self.boundsForTextMarkerRangeAttribute as CFString, range, &rawBounds
        ) == .success,
            let rawBounds, CFGetTypeID(rawBounds) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        let value = unsafeDowncast(rawBounds as AnyObject, to: AXValue.self)
        return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
    }

    private func searchDescendants(of root: AXUIElement) -> ResolvedSelection? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visited = 0

        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > Self.nodeLimit { break }

            if depth > 0, let hit = selection(of: element, strategy: "descendant-\(depth)") {
                return hit
            }
            guard depth < Self.depthLimit else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static let webAreaRole = "AXWebArea"
    private static let selectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
    private static let stringForTextMarkerRangeAttribute = "AXStringForTextMarkerRange"
    private static let boundsForTextMarkerRangeAttribute = "AXBoundsForTextMarkerRange"

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXParentAttribute as CFString, &raw
        ) == .success,
            let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(raw as AnyObject, to: AXUIElement.self)
    }

    private func topLevelElement(of element: AXUIElement) -> AXUIElement? {
        for attribute in [kAXWindowAttribute, kAXTopLevelUIElementAttribute] {
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, attribute as CFString, &raw
            ) == .success,
                let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() {
                return unsafeDowncast(raw as AnyObject, to: AXUIElement.self)
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &raw
        ) == .success,
            let array = raw as? [AnyObject]
        else { return [] }
        return array
            .filter { CFGetTypeID($0) == AXUIElementGetTypeID() }
            .prefix(Self.childLimit)
            .map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    private func role(of element: AXUIElement) -> String {
        stringAttribute(kAXRoleAttribute, from: element) ?? "unknown"
    }

    /// Bounds for the accessibility tree walk. Every attribute read is a
    /// cross-process round trip, so the walk is capped in breadth and depth,
    /// and every message in a capture is bounded by `messagingTimeout` (set
    /// process-wide at the top of `captureSelection`) to keep a large document
    /// or an unresponsive app from stalling the main actor.
    // Page content in browsers nests the focused element many groups deep
    // below the web area, so the (cheap, linear) ancestor walk goes further
    // than the (expensive, branching) descendant search.
    private static let ancestorLimit = 14
    private static let depthLimit = 6
    private static let nodeLimit = 300
    private static let childLimit = 64
    private static let messagingTimeout: Float = 0.25

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rawRange
        ) == .success,
            let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange(location: 0, length: 0)
        let value = unsafeDowncast(rawRange as AnyObject, to: AXValue.self)
        guard AXValueGetValue(value, .cfRange, &range), range.location != kCFNotFound else {
            return nil
        }
        return range
    }

    private func selectionBounds(for range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var rawBounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue, &rawBounds
        ) == .success,
            let rawBounds, CFGetTypeID(rawBounds) == AXValueGetTypeID()
        else { return nil }
        var bounds = CGRect.zero
        let value = unsafeDowncast(rawBounds as AnyObject, to: AXValue.self)
        return AXValueGetValue(value, .cgRect, &bounds) ? bounds : nil
    }

    private func isSecure(_ startingElement: AXUIElement) -> Bool {
        var current: AXUIElement? = startingElement
        for _ in 0..<8 {
            guard let element = current else { break }
            if stringAttribute(kAXSubroleAttribute, from: element)
                == (kAXSecureTextFieldSubrole as String) {
                return true
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXParentAttribute as CFString, &parent
            ) == .success,
                let parent, CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            current = unsafeDowncast(parent as AnyObject, to: AXUIElement.self)
        }
        return false
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func appKitScreenRect(from accessibilityRect: CGRect) -> CGRect {
        // Accessibility coordinates are top-left-relative to the PRIMARY
        // display, so the flip constant is the primary screen's maxY. Using
        // the tallest screen shifts anchors whenever a display is arranged
        // above the primary one.
        guard let screenHeight = NSScreen.screens.first?.frame.maxY else {
            return accessibilityRect
        }
        return CGRect(
            x: accessibilityRect.origin.x,
            y: screenHeight - accessibilityRect.origin.y - accessibilityRect.height,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
    }
}
