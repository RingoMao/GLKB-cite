import AppKit
import ApplicationServices

@MainActor
public protocol AccessibilityPermissionManaging: AnyObject {
    var isTrusted: Bool { get }

    /// Checks the current trust state and, when requested, asks macOS to show its
    /// standard Accessibility consent prompt.
    @discardableResult
    func checkTrust(promptIfNeeded: Bool) -> Bool

    func openAccessibilitySettings()
}

@MainActor
public final class AccessibilityPermissionManager: AccessibilityPermissionManaging {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func checkTrust(promptIfNeeded: Bool) -> Bool {
        // The public constant is imported as mutable legacy C state, which is
        // rejected by Swift 6 concurrency checking. Its documented key value is
        // stable and avoids sharing that unsafe global reference.
        let options = ["AXTrustedCheckOptionPrompt": promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
