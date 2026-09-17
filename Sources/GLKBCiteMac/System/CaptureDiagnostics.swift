import Foundation
import os

/// Opt-in diagnostics for the selection-capture pipeline.
///
/// Capture failures are deliberately silent in automatic mode, which makes
/// "I selected text and nothing happened" impossible to explain. Enabling
/// diagnostics records *why* a capture succeeded or failed.
///
/// Selected text is never logged — only element roles, strategies, character
/// counts, and error codes. Disabled unless the user opts in with:
///
///     defaults write org.glkb.cite diagnostics.captureLoggingEnabled -bool true
public enum CaptureDiagnostics {
    public static let subsystem = "org.glkb.cite"

    private static let logger = Logger(subsystem: subsystem, category: "capture")

    private static let isEnabled: Bool = {
        UserDefaults.standard.bool(forKey: "diagnostics.captureLoggingEnabled")
    }()

    public static func log(_ message: String) {
        guard isEnabled else { return }
        logger.notice("\(message, privacy: .public)")
    }
}
