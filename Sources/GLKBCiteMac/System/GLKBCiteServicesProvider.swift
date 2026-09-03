import AppKit
import Foundation
import GLKBCiteCore

public struct ServiceSelectionEvent: Hashable, Sendable {
    public let selection: SelectionContext

    public init(selection: SelectionContext) {
        self.selection = selection
    }
}

@MainActor
public protocol GLKBCiteServicesProviding: AnyObject {
    func install(
        handler: @escaping @MainActor @Sendable (ServiceSelectionEvent) -> Void
    )
    func uninstall()
}

/// Receives selected text from the private pasteboard macOS creates for a
/// Services invocation. This class never reads or writes `NSPasteboard.general`.
///
/// The application Info.plist declares one `NSServices` entry whose
/// `NSMessage` value is `findGLKBCitations` and whose
/// send types include `public.utf8-plain-text`.
@MainActor
public final class GLKBCiteServicesProvider: NSObject, GLKBCiteServicesProviding {
    private var handler: (@MainActor @Sendable (ServiceSelectionEvent) -> Void)?

    public override init() {
        super.init()
    }

    public func install(
        handler: @escaping @MainActor @Sendable (ServiceSelectionEvent) -> Void
    ) {
        self.handler = handler
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
    }

    public func uninstall() {
        if let provider = NSApplication.shared.servicesProvider as AnyObject?, provider === self {
            NSApplication.shared.servicesProvider = nil
        }
        handler = nil
    }

    @objc(findGLKBCitations:userData:error:)
    public func findGLKBCitations(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        receive(from: pasteboard, error: errorPointer)
    }

    private func receive(
        from servicePasteboard: NSPasteboard,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = servicePasteboard.string(forType: .string),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorPointer.pointee = "GLKB Cite did not receive selected text from this application." as NSString
            return
        }
        guard let handler else {
            errorPointer.pointee = "GLKB Cite is still starting. Please try the Service again." as NSString
            return
        }

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let selection = SelectionContext(
            selectedText: selectedText,
            sourceApplicationName: sourceApplication?.localizedName,
            sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
            bounds: nil,
            isEditable: false,
            captureMethod: .service,
            capturedAt: Date()
        )
        errorPointer.pointee = nil
        handler(ServiceSelectionEvent(selection: selection))
    }
}
