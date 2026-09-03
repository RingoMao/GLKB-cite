import AppKit
import XCTest
@testable import GLKBCiteMac

@MainActor
final class ClipboardCompatibilityCaptureTests: XCTestCase {
    func testNamedPasteboardSnapshotRestoresMultipleItemsAndBinaryTypes() throws {
        let pasteboard = NSPasteboard(name: .init("org.glkb.cite.tests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data("<b>rich</b>".utf8), forType: .html)
        first.setData(Data([0, 1, 2, 255]), forType: .init("org.glkb.binary-test"))
        let second = NSPasteboardItem()
        second.setData(Data("{\\rtf1 test}".utf8), forType: .rtf)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([first, second]) else {
            throw XCTSkip("The pasteboard server is unavailable in this test environment.")
        }

        let adapter = GeneralPasteboardAdapter(pasteboard: pasteboard)
        let snapshot = try adapter.snapshot(maximumBytes: 1_024)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.byteCount, 32)

        pasteboard.clearContents()
        pasteboard.setString("temporary selection", forType: .string)
        XCTAssertTrue(adapter.restore(snapshot, ifCurrentChangeCountIs: pasteboard.changeCount))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?[0].string(forType: .string), "plain")
        XCTAssertEqual(
            pasteboard.pasteboardItems?[0].data(forType: .init("org.glkb.binary-test")),
            Data([0, 1, 2, 255])
        )
        XCTAssertEqual(
            pasteboard.pasteboardItems?[1].data(forType: .rtf),
            Data("{\\rtf1 test}".utf8)
        )
    }

    func testSnapshotFailsClosedAtSizeLimit() throws {
        let pasteboard = NSPasteboard(name: .init("org.glkb.cite.tests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        guard pasteboard.setData(
            Data(repeating: 1, count: 33),
            forType: .init("org.glkb.large")
        ) else {
            throw XCTSkip("The pasteboard server is unavailable in this test environment.")
        }
        let adapter = GeneralPasteboardAdapter(pasteboard: pasteboard)
        XCTAssertThrowsError(try adapter.snapshot(maximumBytes: 32)) { error in
            XCTAssertEqual(error as? ClipboardCaptureError, .snapshotTooLarge)
        }
    }

    func testSuccessfulCaptureRestoresBeforeReturning() async throws {
        let pasteboard = FakePasteboard(originalText: "original")
        let sender = FakeCopySender { pasteboard.publishCopiedText("A scientific selection for citation search.") }
        let capturer = makeCapturer(pasteboard: pasteboard, sender: sender)

        let result = try await capturer.capture(from: source)

        XCTAssertEqual(result.context.captureMethod, .clipboardCompatibility)
        XCTAssertEqual(result.context.selectedText, "A scientific selection for citation search.")
        XCTAssertNil(result.context.bounds)
        XCTAssertFalse(result.context.isEditable)
        XCTAssertEqual(sender.sendCount, 1)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(pasteboard.currentText, "original")
    }

    func testTimeoutAndUnsafeRestoreNeverReturnSelection() async {
        let timedOutPasteboard = FakePasteboard(originalText: "original")
        let timeout = makeCapturer(
            pasteboard: timedOutPasteboard,
            sender: FakeCopySender {}
        )
        do {
            _ = try await timeout.capture(from: source)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ClipboardCaptureError, .copyTimedOut)
        }

        let unsafePasteboard = FakePasteboard(originalText: "original")
        unsafePasteboard.restoreAllowed = false
        let unsafe = makeCapturer(
            pasteboard: unsafePasteboard,
            sender: FakeCopySender {
                unsafePasteboard.publishCopiedText("A scientific selection for citation search.")
            }
        )
        do {
            _ = try await unsafe.capture(from: source)
            XCTFail("Expected restore failure")
        } catch {
            XCTAssertEqual(error as? ClipboardCaptureError, .clipboardRestoreFailed)
        }
    }

    func testSourcePIDChangeRestoresThenFails() async {
        let pasteboard = FakePasteboard(originalText: "original")
        var currentPID: pid_t? = 42
        let sender = FakeCopySender {
            pasteboard.publishCopiedText("A scientific selection for citation search.")
            currentPID = 99
        }
        let capturer = makeCapturer(
            pasteboard: pasteboard,
            sender: sender,
            processProvider: { currentPID }
        )
        do {
            _ = try await capturer.capture(from: source)
            XCTFail("Expected source change")
        } catch {
            XCTAssertEqual(error as? ClipboardCaptureError, .sourceApplicationChanged)
            XCTAssertEqual(pasteboard.currentText, "original")
            XCTAssertEqual(pasteboard.restoreCount, 1)
        }
    }

    func testCancellationRestoresAndSimultaneousCaptureIsBusy() async {
        let pasteboard = FakePasteboard(originalText: "original")
        let sender = FakeCopySender {
            pasteboard.publishCopiedText("A scientific selection for citation search.")
        }
        let capturer = ClipboardCompatibilityCapturer(
            pasteboard: pasteboard,
            commandSender: sender,
            timeoutMilliseconds: 500,
            settleMilliseconds: 300,
            pollMilliseconds: 2,
            frontmostProcessIdentifier: { 42 }
        )
        let first = Task { try await capturer.capture(from: source) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        do {
            _ = try await capturer.capture(from: source)
            XCTFail("Expected busy")
        } catch {
            XCTAssertEqual(error as? ClipboardCaptureError, .busy)
        }
        first.cancel()
        _ = try? await first.value
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(pasteboard.currentText, "original")
    }

    private var source: SelectionSource {
        .init(processIdentifier: 42, applicationName: "Fixture", bundleIdentifier: "org.glkb.fixture")
    }

    private func makeCapturer(
        pasteboard: FakePasteboard,
        sender: FakeCopySender,
        processProvider: @escaping @MainActor @Sendable () -> pid_t? = { 42 }
    ) -> ClipboardCompatibilityCapturer {
        ClipboardCompatibilityCapturer(
            pasteboard: pasteboard,
            commandSender: sender,
            timeoutMilliseconds: 35,
            settleMilliseconds: 2,
            pollMilliseconds: 1,
            frontmostProcessIdentifier: processProvider
        )
    }
}

@MainActor
private final class FakePasteboard: PasteboardAccessing {
    private(set) var changeCount = 10
    private(set) var currentText: String?
    private let original: PasteboardSnapshot
    var restoreAllowed = true
    private(set) var restoreCount = 0

    init(originalText: String) {
        currentText = originalText
        original = PasteboardSnapshot(
            items: [.init(representations: [
                .init(typeIdentifier: NSPasteboard.PasteboardType.string.rawValue, data: Data(originalText.utf8))
            ])],
            startingChangeCount: 10,
            byteCount: originalText.utf8.count
        )
    }

    func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot {
        guard original.byteCount <= maximumBytes else { throw ClipboardCaptureError.snapshotTooLarge }
        return PasteboardSnapshot(
            items: original.items,
            startingChangeCount: changeCount,
            byteCount: original.byteCount
        )
    }

    func string(atStableChangeCount expected: Int) throws -> String {
        guard expected == changeCount, let currentText else {
            throw ClipboardCaptureError.copiedTextUnavailable
        }
        return currentText
    }

    func restore(_ snapshot: PasteboardSnapshot, ifCurrentChangeCountIs expected: Int) -> Bool {
        restoreCount += 1
        guard restoreAllowed, expected == changeCount else { return false }
        currentText = String(data: snapshot.items[0].representations[0].data, encoding: .utf8)
        changeCount += 1
        return true
    }

    func publishCopiedText(_ text: String) {
        currentText = text
        changeCount += 1
    }
}

@MainActor
private final class FakeCopySender: CopyCommandSending {
    private let action: () -> Void
    private(set) var sendCount = 0
    init(action: @escaping () -> Void) { self.action = action }
    func sendCopy(to processIdentifier: pid_t) throws {
        sendCount += 1
        action()
    }
}
