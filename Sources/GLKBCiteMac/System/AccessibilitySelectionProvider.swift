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
}

@MainActor
public protocol AsyncSystemSelectionCapturing: AnyObject {
    func captureSelection(allowCompatibility: Bool) async throws -> SystemSelection
    func isStillValid(_ selection: SystemSelection) async -> Bool
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

        let element = try focusedElement()
        guard !isSecure(element) else { throw SelectionCaptureError.secureField }
        let source = try source(for: element)

        let capturedText: String
        do {
            capturedText = try selectedText(from: element)
        } catch SelectionCaptureError.selectionUnavailable {
            throw SelectionCaptureError.selectionUnavailable(source: source)
        }
        guard !capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionCaptureError.emptySelection
        }

        let selectedRange = selectedTextRange(from: element)
        let bounds = selectedRange
            .flatMap { selectionBounds(for: $0, in: element) }
            .map(appKitScreenRect(from:))
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

    private func selectedText(from element: AXUIElement) throws -> String {
        var rawText: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &rawText
        )
        switch error {
        case .success:
            guard let text = rawText as? String else {
                throw SelectionCaptureError.selectionUnavailable(
                    source: SelectionSource(processIdentifier: 0, applicationName: nil, bundleIdentifier: nil)
                )
            }
            return text
        case .noValue, .attributeUnsupported:
            throw SelectionCaptureError.selectionUnavailable(
                source: SelectionSource(processIdentifier: 0, applicationName: nil, bundleIdentifier: nil)
            )
        default:
            throw SelectionCaptureError.accessibilityFailure(
                operation: "read the selected text", code: error
            )
        }
    }

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
        guard let screenHeight = NSScreen.screens.map(\.frame.maxY).max() else {
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
