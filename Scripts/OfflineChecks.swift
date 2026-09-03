import AppKit
import Foundation
import GLKBCiteCore

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("Offline check failed: \(message)") }
}

@MainActor
@main
struct OfflineChecks {
    static func main() async throws {
        try coreChecks()
        if ProcessInfo.processInfo.environment["GLKB_RUN_KEYCHAIN_INTEGRATION"] == "1" {
            try keychainCheck()
        }
        try pasteboardAdapterCheck()
        try await compatibilityTransactionCheck()
        try await coalescingCheck()
        gestureChecks()
        print("GLKB Cite offline checks passed")
    }

    private static func keychainCheck() throws {
        let store = KeychainGLKBAPIKeyStore(
            service: "org.glkb.cite.offline.\(UUID())",
            account: "Offline test key"
        )
        defer { try? store.deleteAPIKey() }

        let fixtureKey = "glkb_" + "offline_test_only"
        try store.saveAPIKey(fixtureKey)
        let loadedKey = try store.loadAPIKey()
        require(loadedKey == fixtureKey, "standard Keychain save and load")
        try store.deleteAPIKey()
        let deletedKey = try store.loadAPIKey()
        require(deletedKey == nil, "standard Keychain deletion")
    }

    private static func coreChecks() throws {
        let normalized = try LiteratureInputValidator.normalize(
            "  A scientific selection for citation search.  "
        )
        require(normalized == "A scientific selection for citation search.", "normalization")

        let data = Data(#"{"status":"ok","references":[{"pmid":"42","title":"Article"},{"pmid":"42","title":"Duplicate"}]}"#.utf8)
        let result = try GLKBResponseParser.parse(data)
        require(result.references.count == 1, "PMID deduplication")
        require(PubMed.url(for: "42")?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/42/", "PubMed URL")
        require(LiteratureReportFormatter.plainText(result).contains("PMID: 42"), "plain report")

        if CommandLine.arguments.count > 1 {
            let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let fixtureResult = try GLKBResponseParser.parse(fixture)
            require(fixtureResult.references.count == 2, "recorded GLKB fixture")
            require(fixtureResult.references.first?.pmid == "38743124", "fixture PMID")
        }
    }

    private static func pasteboardAdapterCheck() throws {
        let pasteboard = NSPasteboard(name: .init("org.glkb.cite.offline.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        first.setData(Data("<b>rich</b>".utf8), forType: .html)
        first.setData(Data([0, 1, 255]), forType: .init("org.glkb.binary"))
        let second = NSPasteboardItem()
        second.setData(Data("{\\rtf1 test}".utf8), forType: .rtf)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([first, second]) else {
            print("Named pasteboard adapter check skipped: pasteboard server unavailable")
            return
        }

        let adapter = GeneralPasteboardAdapter(pasteboard: pasteboard)
        let snapshot = try adapter.snapshot(maximumBytes: 1_024)
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        require(adapter.restore(snapshot, ifCurrentChangeCountIs: pasteboard.changeCount), "restore named pasteboard")
        require(pasteboard.pasteboardItems?.count == 2, "restore item count")
        require(pasteboard.pasteboardItems?[0].string(forType: .string) == "original", "restore text")
        require(
            pasteboard.pasteboardItems?[0].data(forType: .init("org.glkb.binary")) == Data([0, 1, 255]),
            "restore binary type"
        )
    }

    private static func compatibilityTransactionCheck() async throws {
        let pasteboard = OfflinePasteboard()
        let sender = OfflineCopySender(pasteboard: pasteboard)
        let capture = ClipboardCompatibilityCapturer(
            pasteboard: pasteboard,
            commandSender: sender,
            timeoutMilliseconds: 50,
            settleMilliseconds: 2,
            pollMilliseconds: 1,
            frontmostProcessIdentifier: { 42 }
        )
        let result = try await capture.capture(
            from: .init(
                processIdentifier: 42,
                applicationName: "Fixture",
                bundleIdentifier: "org.glkb.fixture"
            )
        )
        require(result.context.captureMethod == .clipboardCompatibility, "capture provenance")
        require(result.context.bounds == nil && !result.context.isEditable, "clipboard capture safety")
        require(pasteboard.text == "original", "restore before returning")
        require(pasteboard.restoreCount == 1, "one restore")
    }

    private static func coalescingCheck() async throws {
        let counter = OfflineCounter()
        let backend = OfflineBackend(counter: counter)
        let decorated = CachingLiteratureBackend(backend: backend, endpointScope: "offline")
        let query = LiteratureQuery(
            text: "A simultaneous scientific selection for citation search.",
            options: .init(cacheDurationMinutes: 15)
        )
        async let first = completed(decorated.query(query))
        async let second = completed(decorated.query(query))
        _ = try await (first, second)
        let countAfterConcurrent = await counter.value
        require(countAfterConcurrent == 1, "in-flight coalescing")
        let cached = try await completed(decorated.query(query))
        require(cached.isCached, "completed cache hit")
        let countAfterCache = await counter.value
        require(countAfterCache == 1, "cache avoids paid request")
    }

    private static func completed(
        _ stream: AsyncThrowingStream<LiteratureQueryEvent, Error>
    ) async throws -> LiteratureResult {
        for try await event in stream {
            if case .completed(let result) = event { return result }
        }
        throw LiteratureError.malformedResponse("missing completion")
    }

    private static func gestureChecks() {
        let point = SystemPoint(x: 0, y: 0)
        require(!SelectionGesture(start: point, end: point, clickCount: 1, shiftPressed: false, observedDrag: false).isCompatibilityEligible, "caret rejection")
        require(SelectionGesture(start: point, end: point, clickCount: 2, shiftPressed: false, observedDrag: false).isCompatibilityEligible, "double click")
        require(SelectionGesture(start: point, end: .init(x: 10, y: 0), clickCount: 1, shiftPressed: false, observedDrag: true).isCompatibilityEligible, "drag")
    }
}

@MainActor
private final class OfflinePasteboard: PasteboardAccessing {
    private(set) var changeCount = 1
    private(set) var text = "original"
    private(set) var restoreCount = 0

    func snapshot(maximumBytes: Int) throws -> PasteboardSnapshot {
        .init(
            items: [.init(representations: [.init(
                typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                data: Data(text.utf8)
            )])],
            startingChangeCount: changeCount,
            byteCount: text.utf8.count
        )
    }

    func string(atStableChangeCount expected: Int) throws -> String {
        guard expected == changeCount else { throw ClipboardCaptureError.clipboardChangedDuringCapture }
        return text
    }

    func restore(_ snapshot: PasteboardSnapshot, ifCurrentChangeCountIs expected: Int) -> Bool {
        guard expected == changeCount else { return false }
        restoreCount += 1
        text = String(data: snapshot.items[0].representations[0].data, encoding: .utf8)!
        changeCount += 1
        return true
    }

    func publishSelection() {
        text = "A scientific selection for citation search."
        changeCount += 1
    }
}

@MainActor
private final class OfflineCopySender: CopyCommandSending {
    let pasteboard: OfflinePasteboard
    init(pasteboard: OfflinePasteboard) { self.pasteboard = pasteboard }
    func sendCopy(to processIdentifier: pid_t) throws { pasteboard.publishSelection() }
}

private actor OfflineCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct OfflineBackend: LiteratureBackend {
    let counter: OfflineCounter
    func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await counter.increment()
                try? await Task.sleep(nanoseconds: 30_000_000)
                continuation.yield(.completed(.init(
                    answer: "Grounded",
                    references: [.init(pmid: "42", title: "Article")]
                )))
                continuation.finish()
            }
        }
    }
}
