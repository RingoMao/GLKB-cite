import Foundation
import os

/// Opt-in diagnostics for the selection-capture pipeline.
///
/// Capture failures are deliberately silent in automatic mode, which makes
/// "I selected text and nothing happened" impossible to explain. Enabling
/// diagnostics records *why* a capture succeeded or failed.
///
/// Selected text is never logged. What is logged: element roles, search
/// strategies, character counts, error codes, and the bundle identifier of
/// the app the selection was made in. Disabled unless the user opts in with:
///
///     defaults write org.glkb.cite diagnostics.captureLoggingEnabled -bool true
public enum CaptureDiagnostics {
    public static let subsystem = "org.glkb.cite"

    private static let logger = Logger(subsystem: subsystem, category: "capture")

    private static let isEnabled: Bool = {
        UserDefaults.standard.bool(forKey: "diagnostics.captureLoggingEnabled")
    }()

    /// The message is an autoclosure so call sites pay nothing (no string
    /// building, no attribute reads) while diagnostics are off.
    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }
}
