import Foundation
import GLKBCiteCore
import XCTest
@testable import GLKBCiteMac

@MainActor
final class SelectionCaptureRoutingTests: XCTestCase {
    func testAccessibilitySuccessNeverTouchesCompatibilityCapture() async throws {
        let selection = fixtureSelection(method: .accessibility)
        let accessibility = StubAccessibility(result: .success(selection))
        let pasteboard = RoutingPasteboard()
        let sender = RoutingCopySender(pasteboard: pasteboard)
        let provider = CompositeSelectionProvider(
            accessibility: accessibility,
            compatibility: compatibility(pasteboard: pasteboard, sender: sender),
            compatibilityEnabled: { true }
        )

        let result = try await provider.captureSelection(allowCompatibility: true)
        XCTAssertEqual(result, selection)
        XCTAssertEqual(sender.sendCount, 0)
    }

    func testSecureFieldAndDisabledFallbackNeverPostCopy() async {
        for error in [
            SelectionCaptureError.secureField,
            SelectionCaptureError.selectionUnavailable(source: source)
        ] {
            let pasteboard = RoutingPasteboard()
            let sender = RoutingCopySender(pasteboard: pasteboard)
            let provider = CompositeSelectionProvider(
                accessibility: StubAccessibility(result: .failure(error)),
                compatibility: compatibility(pasteboard: pasteboard, sender: sender),
                compatibilityEnabled: { false }
            )
            do {
                _ = try await provider.captureSelection(allowCompatibility: true)
                XCTFail("Expected capture failure")
            } catch {}
            XCTAssertEqual(sender.sendCount, 0)
        }
    }

    func testUnsupportedAXUsesCompatibilityOnlyWhenExplicitlyEligible() async throws {
        let pasteboard = RoutingPasteboard()
        let sender = RoutingCopySender(pasteboard: pasteboard)
        let provider = CompositeSelectionProvider(
            accessibility: StubAccessibility(
                result: .failure(SelectionCaptureError.selectionUnavailable(source: source))
            ),
            compatibility: compatibility(pasteboard: pasteboard, sender: sender),
            compatibilityEnabled: { true }
        )

        do {
            _ = try await provider.captureSelection(allowCompatibility: false)
            XCTFail("Expected ineligible capture failure")
        } catch {}
        XCTAssertEqual(sender.sendCount, 0)

        let captured = try await provider.captureSelection(allowCompatibility: true)
        XCTAssertEqual(captured.context.captureMethod, .clipboardCompatibility)
        XCTAssertEqual(sender.sendCount, 1)
    }

    private var source: SelectionSource {
        .init(processIdentifier: 42, applicationName: "Fixture", bundleIdentifier: "org.glkb.fixture")
    }

    private func fixtureSelection(method: SelectionCaptureMethod) -> SystemSelection {
        SystemSelection(
            context: .init(
                selectedText: "A scientific selection for citation search.",
                captureMethod: method
            ),
            sourceProcessIdentifier: 42
        )
    }

    private func compatibility(
        pasteboard: RoutingPasteboard,
        sender: RoutingCopySender
    ) -> ClipboardCompatibilityCapturer {
        ClipboardCompatibilityCapturer(
            pasteboard: pasteboard,
            commandSender: sender,
            timeoutMilliseconds: 30,
            settleMilliseconds: 1,
            pollMilliseconds: 1,
            frontmostProcessIdentifier: { 42 }
        )
    }
}

@MainActor
private final class StubAccessibility: AccessibilitySelectionCapturing {
    let result: Result<SystemSelection, Error>
    init(result: Result<SystemSelection, Error>) { self.result = result }
    func captureSelection() throws -> SystemSelection { try result.get() }
}

@MainActor
private final class RoutingPasteboard: PasteboardAccessing {
    private(set) var changeCount = 1
    private var text = "original"
    func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot {
        .init(items: [], startingChangeCount: changeCount, byteCount: 0)
    }
    func string(atStableChangeCount expected: Int) throws -> String {
        guard expected == changeCount else { throw ClipboardCaptureError.clipboardChangedDuringCapture }
        return text
    }
    func restore(_ snapshot: PasteboardSnapshot, ifCurrentChangeCountIs expected: Int) -> Bool {
        guard expected == changeCount else { return false }
        text = "original"
        changeCount += 1
        return true
    }
    func publishSelection() {
        text = "A scientific selection for citation search."
        changeCount += 1
    }
}

@MainActor
private final class RoutingCopySender: CopyCommandSending {
    let pasteboard: RoutingPasteboard
    private(set) var sendCount = 0
    init(pasteboard: RoutingPasteboard) { self.pasteboard = pasteboard }
    func sendCopy(to processIdentifier: pid_t) throws {
        sendCount += 1
        pasteboard.publishSelection()
    }
}
