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
    case clipboardConcealed
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
        case .clipboardConcealed:
            "The clipboard holds concealed content (for example from a password manager), so GLKB Cite did not copy the selection. Copy something else first, or select the text in an app that supports Accessibility."
        case .sourceApplicationChanged:
            "The active application changed before the selection could be captured."
        case .clipboardChangedBeforeCopy:
            "The clipboard changed before capture began. Try again."
        case .copyEventFailed:
            "macOS could not send Copy to the selected application."
        case .copyTimedOut:
            "The selected application did not provide copied text in time. If it copies later, the previous clipboard content may be replaced by the selection."
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

    /// Marker types that password managers and clipboard utilities attach to
    /// sensitive or temporary items. Such clipboards are never snapshotted:
    /// materializing them would copy a secret into this process and restoring
    /// them would republish it as a fresh clipboard change.
    static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot {
        let startingChangeCount = pasteboard.changeCount
        let pasteboardItems = pasteboard.pasteboardItems ?? []

        // Refuse up front, before any data provider is asked for bytes.
        for item in pasteboardItems {
            let types = item.types.map(\.rawValue)
            if types.contains(where: { Self.concealedTypes.contains($0) }) {
                throw ClipboardCaptureError.clipboardConcealed
            }
            // File promises materialize by invoking the promising app's
            // provider (and may write files); they cannot be round-tripped.
            if types.contains(where: { $0.hasPrefix("com.apple.pasteboard.promised-") }) {
                throw ClipboardCaptureError.snapshotCouldNotMaterialize
            }
        }

        var byteCount = 0
        let items = try pasteboardItems.map { item in
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
        if pasteboard.writeObjects(items) { return true }
        // The pasteboard server refused the full set. Rather than leave the
        // clipboard empty, put back at least the original plain text so the
        // user still has something to paste; the caller still reports failure.
        if let text = snapshot.items
            .flatMap(\.representations)
            .first(where: { $0.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue })
            .flatMap({ String(data: $0.data, encoding: .utf8) }) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        return false
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
    private let extendedTimeoutNanoseconds: UInt64
    private let settleNanoseconds: UInt64
    private let pollNanoseconds: UInt64
    private var isCapturing = false
    /// The user's clipboard as it was before Copy was sent, kept until it has
    /// been put back, so an interrupted capture (cancellation, quit) can still
    /// restore it.
    private var pendingRestore: (snapshot: PasteboardSnapshot, copiedChangeCount: Int)?

    /// - Parameters:
    ///   - timeoutMilliseconds: how long the target app normally gets to
    ///     honour Copy.
    ///   - extendedTimeoutMilliseconds: how long to keep waiting beyond that
    ///     while the target app is still frontmost, so a slow app that copies
    ///     late does not leave the user's previous clipboard overwritten
    ///     after we have already given up. Defaults to four times the timeout.
    public convenience init(
        maximumBytes: Int = 32 * 1_024 * 1_024,
        timeoutMilliseconds: UInt64 = 750,
        extendedTimeoutMilliseconds: UInt64? = nil,
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
            extendedTimeoutMilliseconds: extendedTimeoutMilliseconds,
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
        extendedTimeoutMilliseconds: UInt64? = nil,
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
        extendedTimeoutNanoseconds = (extendedTimeoutMilliseconds ?? timeoutMilliseconds * 4) * 1_000_000
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
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .nanoseconds(Int64(clamping: timeoutNanoseconds)))
        let extendedDeadline = started.advanced(
            by: .nanoseconds(Int64(clamping: max(timeoutNanoseconds, extendedTimeoutNanoseconds)))
        )

        do {
            while ContinuousClock.now < extendedDeadline {
                try Task.checkCancellation()
                let current = pasteboard.changeCount
                if current != original.startingChangeCount {
                    if current != copiedChangeCount {
                        copiedChangeCount = current
                        pendingRestore = (original, current)
                        lastChangeAt = .now
                    } else if ContinuousClock.now - lastChangeAt >= .nanoseconds(
                        Int64(clamping: settleNanoseconds)
                    ) {
                        break
                    }
                } else if ContinuousClock.now >= deadline,
                          frontmostProcessIdentifier() != source.processIdentifier {
                    // Past the normal timeout and the user has moved on; a
                    // late Copy from that app is no longer expected.
                    break
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
            pendingRestore = nil

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
            if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
                let restored = pasteboard.restore(original, ifCurrentChangeCountIs: copiedChangeCount)
                pendingRestore = nil
                if !restored { throw ClipboardCaptureError.clipboardRestoreFailed }
            } else if copiedChangeCount != nil {
                // Someone else changed the clipboard after the copy; the newer
                // content wins and there is nothing left for us to put back.
                pendingRestore = nil
            }
            throw error
        }
    }

    /// Synchronously restores the clipboard if a capture was interrupted
    /// after Copy had replaced it but before it was put back. Safe to call at
    /// any time, including from application termination.
    public func restorePendingSnapshotIfNeeded() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        guard pasteboard.changeCount == pending.copiedChangeCount else { return }
        _ = pasteboard.restore(pending.snapshot, ifCurrentChangeCountIs: pending.copiedChangeCount)
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

    public func captureSelection(_ options: SelectionCaptureOptions) async throws -> SystemSelection {
        do {
            let selection = try accessibility.captureSelection(descendantSearch: options.descendantSearch)
            if let expected = options.expectedProcess, selection.sourceProcessIdentifier != expected {
                throw SelectionCaptureError.staleSelection
            }
            return selection
        } catch let SelectionCaptureError.selectionUnavailable(source) {
            guard options.allowCompatibility, compatibilityEnabled() else {
                throw SelectionCaptureError.selectionUnavailable(source: source)
            }
            // Never post Copy into a process other than the one the request
            // was made for.
            if let expected = options.expectedProcess, source.processIdentifier != expected {
                throw SelectionCaptureError.staleSelection
            }
            return try await compatibility.capture(from: source)
        }
    }

    public func focusedElementIsItemContainer() -> Bool {
        accessibility.focusedElementIsItemContainer()
    }

    public func gestureLandsInContent(from start: CGPoint, to end: CGPoint) -> Bool {
        accessibility.gestureLandsInContent(from: start, to: end)
    }

    public func restorePendingClipboardIfNeeded() {
        compatibility.restorePendingSnapshotIfNeeded()
    }

    public func isStillValid(_ selection: SystemSelection) async -> Bool {
        switch selection.context.captureMethod {
        case .accessibility:
            guard let current = try? accessibility.captureSelection(descendantSearch: .thorough) else {
                return false
            }
            return current.sourceProcessIdentifier == selection.sourceProcessIdentifier
                && current.context.selectedText == selection.context.selectedText
        case .clipboardCompatibility, .service:
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
                == selection.sourceProcessIdentifier
                && Date().timeIntervalSince(selection.context.capturedAt) <= 8
        }
    }
}
