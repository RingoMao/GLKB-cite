import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import GLKBCiteCore

public struct PasteboardRepresentationSnapshot: Hashable, Sendable {
    public let typeIdentifier: String
    public let data: Data
}

public struct PasteboardItemSnapshot: Hashable, Sendable {
    public let representations: [PasteboardRepresentationSnapshot]
}

public struct PasteboardSnapshot: Hashable, Sendable {
    public let items: [PasteboardItemSnapshot]
    public let startingChangeCount: Int
    public let byteCount: Int
}

public enum ClipboardCaptureError: Error, LocalizedError, Equatable {
    case disabled
    case busy
    case snapshotTooLarge
    case snapshotCouldNotMaterialize
    case sourceApplicationChanged
    case clipboardChangedBeforeCopy
    case copyEventFailed
    case copyTimedOut
    case copiedTextUnavailable
    case clipboardChangedDuringCapture
    case clipboardRestoreFailed

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "Compatibility Capture is disabled in Privacy Settings."
        case .busy:
            "Another selection capture is already in progress."
        case .snapshotTooLarge:
            "The clipboard is too large to preserve safely, so GLKB Cite did not copy the selection."
        case .snapshotCouldNotMaterialize:
            "The clipboard contains data that cannot be preserved safely."
        case .sourceApplicationChanged:
            "The active application changed before the selection could be captured."
        case .clipboardChangedBeforeCopy:
            "The clipboard changed before capture began. Try again."
        case .copyEventFailed:
            "macOS could not send Copy to the selected application."
        case .copyTimedOut:
            "The selected application did not provide copied text in time."
        case .copiedTextUnavailable:
            "Copy did not produce usable text."
        case .clipboardChangedDuringCapture:
            "Another app changed the clipboard, so GLKB Cite left the newer content untouched."
        case .clipboardRestoreFailed:
            "GLKB Cite could not safely restore the clipboard, so no citation request was sent."
        }
    }
}

@MainActor
public protocol PasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot
    func string(atStableChangeCount expected: Int) throws -> String
    func restore(_ snapshot: PasteboardSnapshot, ifCurrentChangeCountIs expected: Int) -> Bool
}

@MainActor
public final class GeneralPasteboardAdapter: PasteboardAccessing {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot {
        let startingChangeCount = pasteboard.changeCount
        var byteCount = 0
        let items = try (pasteboard.pasteboardItems ?? []).map { item in
            let representations = try item.types.map { type in
                guard let data = item.data(forType: type) else {
                    throw ClipboardCaptureError.snapshotCouldNotMaterialize
                }
                byteCount += data.count
                guard byteCount <= maximumBytes else {
                    throw ClipboardCaptureError.snapshotTooLarge
                }
                return PasteboardRepresentationSnapshot(
                    typeIdentifier: type.rawValue,
                    data: data
                )
            }
            return PasteboardItemSnapshot(representations: representations)
        }
        guard pasteboard.changeCount == startingChangeCount else {
            throw ClipboardCaptureError.clipboardChangedBeforeCopy
        }
        return PasteboardSnapshot(
            items: items,
            startingChangeCount: startingChangeCount,
            byteCount: byteCount
        )
    }

    public func string(atStableChangeCount expected: Int) throws -> String {
        guard pasteboard.changeCount == expected,
              let string = pasteboard.string(forType: .string),
              pasteboard.changeCount == expected else {
            throw ClipboardCaptureError.copiedTextUnavailable
        }
        return string
    }

    public func restore(
        _ snapshot: PasteboardSnapshot,
        ifCurrentChangeCountIs expected: Int
    ) -> Bool {
        guard pasteboard.changeCount == expected else { return false }
        let items: [NSPasteboardItem] = snapshot.items.compactMap { snapshotItem in
            let item = NSPasteboardItem()
            for representation in snapshotItem.representations {
                guard item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.typeIdentifier)
                ) else { return nil }
            }
            return item
        }
        guard items.count == snapshot.items.count else { return false }
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }
        return pasteboard.writeObjects(items)
    }
}

@MainActor
public protocol CopyCommandSending: AnyObject {
    func sendCopy(to processIdentifier: pid_t) throws
}

@MainActor
public final class TargetedCopyCommandSender: CopyCommandSending {
    public init() {}

    public func sendCopy(to processIdentifier: pid_t) throws {
        guard processIdentifier > 0,
              let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
              ) else {
            throw ClipboardCaptureError.copyEventFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
    }
}

@MainActor
public final class ClipboardCompatibilityCapturer {
    public typealias ProcessProvider = @MainActor @Sendable () -> pid_t?

    private let pasteboard: any PasteboardAccessing
    private let commandSender: any CopyCommandSending
    private let frontmostProcessIdentifier: ProcessProvider
    private let maximumBytes: Int
    private let timeoutNanoseconds: UInt64
    private let settleNanoseconds: UInt64
    private let pollNanoseconds: UInt64
    private var isCapturing = false

    public convenience init(
        maximumBytes: Int = 32 * 1_024 * 1_024,
        timeoutMilliseconds: UInt64 = 750,
        settleMilliseconds: UInt64 = 60,
        pollMilliseconds: UInt64 = 15,
        frontmostProcessIdentifier: @escaping ProcessProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.init(
            pasteboard: GeneralPasteboardAdapter(),
            commandSender: TargetedCopyCommandSender(),
            maximumBytes: maximumBytes,
            timeoutMilliseconds: timeoutMilliseconds,
            settleMilliseconds: settleMilliseconds,
            pollMilliseconds: pollMilliseconds,
            frontmostProcessIdentifier: frontmostProcessIdentifier
        )
    }

    public init(
        pasteboard: any PasteboardAccessing,
        commandSender: any CopyCommandSending,
        maximumBytes: Int = 32 * 1_024 * 1_024,
        timeoutMilliseconds: UInt64 = 750,
        settleMilliseconds: UInt64 = 60,
        pollMilliseconds: UInt64 = 15,
        frontmostProcessIdentifier: @escaping ProcessProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.pasteboard = pasteboard
        self.commandSender = commandSender
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.maximumBytes = maximumBytes
        timeoutNanoseconds = timeoutMilliseconds * 1_000_000
        settleNanoseconds = settleMilliseconds * 1_000_000
        pollNanoseconds = max(1, pollMilliseconds) * 1_000_000
    }

    public func capture(from source: SelectionSource) async throws -> SystemSelection {
        guard !isCapturing else { throw ClipboardCaptureError.busy }
        isCapturing = true
        defer { isCapturing = false }

        guard frontmostProcessIdentifier() == source.processIdentifier else {
            throw ClipboardCaptureError.sourceApplicationChanged
        }
        let original = try pasteboard.snapshot(maximumBytes: maximumBytes)
        guard pasteboard.changeCount == original.startingChangeCount else {
            throw ClipboardCaptureError.clipboardChangedBeforeCopy
        }
        guard frontmostProcessIdentifier() == source.processIdentifier else {
            throw ClipboardCaptureError.sourceApplicationChanged
        }

        try commandSender.sendCopy(to: source.processIdentifier)

        var copiedChangeCount: Int?
        var lastChangeAt = ContinuousClock.now
        let deadline = ContinuousClock.now.advanced(
            by: .nanoseconds(Int64(clamping: timeoutNanoseconds))
        )

        do {
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let current = pasteboard.changeCount
                if current != original.startingChangeCount {
                    if current != copiedChangeCount {
                        copiedChangeCount = current
                        lastChangeAt = .now
                    } else if ContinuousClock.now - lastChangeAt >= .nanoseconds(
                        Int64(clamping: settleNanoseconds)
                    ) {
                        break
                    }
                }
                try await Task.sleep(nanoseconds: pollNanoseconds)
            }

            guard let copiedChangeCount else { throw ClipboardCaptureError.copyTimedOut }
            guard pasteboard.changeCount == copiedChangeCount else {
                throw ClipboardCaptureError.clipboardChangedDuringCapture
            }
            let copiedText = try pasteboard.string(atStableChangeCount: copiedChangeCount)
            let normalized = try LiteratureInputValidator.normalize(copiedText)
            guard frontmostProcessIdentifier() == source.processIdentifier else {
                throw ClipboardCaptureError.sourceApplicationChanged
            }
            guard pasteboard.restore(original, ifCurrentChangeCountIs: copiedChangeCount) else {
                throw ClipboardCaptureError.clipboardRestoreFailed
            }

            let context = SelectionContext(
                selectedText: normalized,
                sourceApplicationName: source.applicationName,
                sourceBundleIdentifier: source.bundleIdentifier,
                bounds: nil,
                isEditable: false,
                captureMethod: .clipboardCompatibility
            )
            return SystemSelection(
                context: context,
                sourceProcessIdentifier: source.processIdentifier
            )
        } catch {
            if let copiedChangeCount,
               pasteboard.changeCount == copiedChangeCount,
               !pasteboard.restore(original, ifCurrentChangeCountIs: copiedChangeCount) {
                throw ClipboardCaptureError.clipboardRestoreFailed
            }
            throw error
        }
    }
}

@MainActor
public final class CompositeSelectionProvider: AsyncSystemSelectionCapturing {
    public typealias CompatibilityEnabledProvider = @MainActor @Sendable () -> Bool

    private let accessibility: any AccessibilitySelectionCapturing
    private let compatibility: ClipboardCompatibilityCapturer
    private let compatibilityEnabled: CompatibilityEnabledProvider

    public convenience init(
        accessibility: any AccessibilitySelectionCapturing,
        compatibilityEnabled: @escaping CompatibilityEnabledProvider
    ) {
        self.init(
            accessibility: accessibility,
            compatibility: ClipboardCompatibilityCapturer(),
            compatibilityEnabled: compatibilityEnabled
        )
    }

    public init(
        accessibility: any AccessibilitySelectionCapturing,
        compatibility: ClipboardCompatibilityCapturer,
        compatibilityEnabled: @escaping CompatibilityEnabledProvider
    ) {
        self.accessibility = accessibility
        self.compatibility = compatibility
        self.compatibilityEnabled = compatibilityEnabled
    }

    public func captureSelection(allowCompatibility: Bool) async throws -> SystemSelection {
        do {
            return try accessibility.captureSelection()
        } catch let SelectionCaptureError.selectionUnavailable(source) {
            guard allowCompatibility, compatibilityEnabled() else { throw SelectionCaptureError.selectionUnavailable(source: source) }
            return try await compatibility.capture(from: source)
        }
    }

    public func isStillValid(_ selection: SystemSelection) async -> Bool {
        switch selection.context.captureMethod {
        case .accessibility:
            guard let current = try? accessibility.captureSelection() else { return false }
            return current.sourceProcessIdentifier == selection.sourceProcessIdentifier
                && current.context.selectedText == selection.context.selectedText
        case .clipboardCompatibility, .service:
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
                == selection.sourceProcessIdentifier
                && Date().timeIntervalSince(selection.context.capturedAt) <= 8
        }
    }
}
