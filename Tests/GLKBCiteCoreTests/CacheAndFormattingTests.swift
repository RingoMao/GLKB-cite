import Foundation
import XCTest
@testable import GLKBCiteCore

final class CacheAndFormattingTests: XCTestCase {
    func testCacheKeyIsDeterministicOpaqueAndScoped() {
        let query = LiteratureQuery(
            text: "  SLC30A8  affects diabetes risk. ",
            options: .init(maxArticles: 5)
        )
        let first = LiteratureCacheKey.make(
            query: query,
            endpointScope: "glkb-production",
            credentialScope: "account-a"
        )
        let whitespaceEquivalent = LiteratureCacheKey.make(
            query: .init(
                text: "SLC30A8 affects diabetes risk.",
                options: .init(maxArticles: 5)
            ),
            endpointScope: "glkb-production",
            credentialScope: "account-a"
        )
        let otherAccount = LiteratureCacheKey.make(
            query: query,
            endpointScope: "glkb-production",
            credentialScope: "account-b"
        )

        XCTAssertEqual(first, whitespaceEquivalent)
        XCTAssertNotEqual(first, otherAccount)
        XCTAssertEqual(first.digest.count, 64)
        XCTAssertFalse(first.digest.contains("SLC30A8"))
    }

    func testCitationEvidenceToggleDoesNotChangePaidRequestCacheKey() {
        let base = LiteratureQuery(
            text: "A complete scientific statement for citation search.",
            options: .init(includeEvidence: true)
        )
        let hiddenEvidence = LiteratureQuery(
            text: base.text,
            options: .init(includeEvidence: false)
        )

        XCTAssertEqual(
            LiteratureCacheKey.make(query: base, endpointScope: "glkb", credentialScope: "a"),
            LiteratureCacheKey.make(
                query: hiddenEvidence,
                endpointScope: "glkb",
                credentialScope: "a"
            )
        )
    }

    func testCacheReturnsMarkedCopyAndExpires() async {
        let clock = FixtureClock(Date(timeIntervalSince1970: 1_000))
        let cache = InMemoryLiteratureCache(now: { clock.now })
        let key = LiteratureCacheKey(digest: "one")
        let result = fixtureResult()

        await cache.insert(result, for: key, minutes: 5)
        let cached = await cache.value(for: key)
        XCTAssertEqual(cached?.isCached, true)
        XCTAssertFalse(result.isCached)

        clock.advance(301)
        let expired = await cache.value(for: key)
        let expiredCount = await cache.count
        XCTAssertNil(expired)
        XCTAssertEqual(expiredCount, 0)
    }

    func testCacheEvictsOldestEntryAtCapacity() async {
        let cache = InMemoryLiteratureCache(maximumEntries: 2)
        await cache.insert(fixtureResult(answer: "one"), for: .init(digest: "1"), minutes: 5)
        await cache.insert(fixtureResult(answer: "two"), for: .init(digest: "2"), minutes: 5)
        await cache.insert(fixtureResult(answer: "three"), for: .init(digest: "3"), minutes: 5)

        let first = await cache.value(for: .init(digest: "1"))
        let second = await cache.value(for: .init(digest: "2"))
        let third = await cache.value(for: .init(digest: "3"))
        XCTAssertNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
    }

    func testCachingDecoratorAvoidsSecondBackendCall() async throws {
        let counter = AsyncCounter()
        let backend = FixtureBackend(counter: counter, result: fixtureResult())
        let caching = CachingLiteratureBackend(
            backend: backend,
            endpointScope: "fixture"
        )
        let query = LiteratureQuery(
            text: "A complete claim suitable for the citation backend.",
            options: .init(cacheDurationMinutes: 15)
        )

        let first = try await Self.completedResult(from: caching.query(query))
        let second = try await Self.completedResult(from: caching.query(query))
        XCTAssertFalse(first.isCached)
        XCTAssertTrue(second.isCached)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testZeroMinuteCacheAlwaysCallsBackend() async throws {
        let counter = AsyncCounter()
        let backend = FixtureBackend(counter: counter, result: fixtureResult())
        let caching = CachingLiteratureBackend(backend: backend, endpointScope: "fixture")
        let query = LiteratureQuery(
            text: "A complete claim suitable for the citation backend.",
            options: .init(cacheDurationMinutes: 0)
        )
        _ = try await Self.completedResult(from: caching.query(query))
        _ = try await Self.completedResult(from: caching.query(query))
        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    func testSimultaneousIdenticalQueriesShareOnePaidRequest() async throws {
        let counter = AsyncCounter()
        let backend = FixtureBackend(
            counter: counter,
            result: fixtureResult(),
            delayNanoseconds: 40_000_000
        )
        let caching = CachingLiteratureBackend(backend: backend, endpointScope: "fixture")
        let query = LiteratureQuery(
            text: "A simultaneous scientific claim for citation retrieval.",
            options: .init(cacheDurationMinutes: 15)
        )

        async let first = Self.completedResult(from: caching.query(query))
        async let second = Self.completedResult(from: caching.query(query))
        _ = try await (first, second)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testCancelledMemberReturnsAtOnceWhileOthersKeepTheSharedRequest() async throws {
        let inFlight = InFlightLiteratureRequests()
        let observer = CancellationObserver()
        let key = LiteratureCacheKey(digest: "shared")
        let expected = fixtureResult()
        let slow: @Sendable () async throws -> LiteratureResult = {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                await observer.markCancelled()
                throw error
            }
            return expected
        }
        let first = Task { try await inFlight.result(for: key, operation: slow) }
        let second = Task { try await inFlight.result(for: key, operation: slow) }
        try await Task.sleep(nanoseconds: 40_000_000)
        let countWhileShared = await inFlight.count
        XCTAssertEqual(countWhileShared, 1)

        let clock = ContinuousClock()
        let cancelledAt = clock.now
        first.cancel()
        let firstOutcome = await first.result
        XCTAssertLessThan(clock.now - cancelledAt, .milliseconds(250))
        guard case .failure(let error) = firstOutcome else { return XCTFail("Expected cancellation") }
        XCTAssertTrue(error is CancellationError, "\(error)")

        let secondResult = try await second.value
        XCTAssertEqual(secondResult, expected)
        let wasCancelled = await observer.cancelled
        XCTAssertFalse(wasCancelled)
        let countAfter = await inFlight.count
        XCTAssertEqual(countAfter, 0)
    }

    func testLastMemberLeavingCancelsTheSharedRequest() async throws {
        let inFlight = InFlightLiteratureRequests()
        let observer = CancellationObserver()
        let key = LiteratureCacheKey(digest: "abandoned")
        let slow: @Sendable () async throws -> LiteratureResult = {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                await observer.markCancelled()
                throw error
            }
            return LiteratureResult(answer: "late", references: [])
        }
        let first = Task { try await inFlight.result(for: key, operation: slow) }
        let second = Task { try await inFlight.result(for: key, operation: slow) }
        try await Task.sleep(nanoseconds: 40_000_000)
        first.cancel()
        second.cancel()
        _ = await first.result
        _ = await second.result
        try await Task.sleep(nanoseconds: 60_000_000)
        let wasCancelled = await observer.cancelled
        XCTAssertTrue(wasCancelled, "the paid request kept running with nobody waiting")
        let count = await inFlight.count
        XCTAssertEqual(count, 0)

        // A later caller for the same key starts a fresh request.
        let fresh = try await inFlight.result(for: key) { LiteratureResult(answer: "fresh", references: []) }
        XCTAssertEqual(fresh.answer, "fresh")
    }

    func testCachingDecoratorPropagatesCancellationToTheBackend() async throws {
        let counter = AsyncCounter()
        let observer = CancellationObserver()
        let backend = ObservingBackend(counter: counter, observer: observer, result: fixtureResult())
        let caching = CachingLiteratureBackend(backend: backend, endpointScope: "fixture")
        let query = LiteratureQuery(
            text: "A cancellable scientific claim for citation retrieval.",
            options: .init(cacheDurationMinutes: 15)
        )
        // Named explicitly: `Self.` inside the closure makes older Swift 6
        // compilers capture the (non-Sendable) test case.
        let consumer = Task { try await CacheAndFormattingTests.completedResult(from: caching.query(query)) }
        try await Task.sleep(nanoseconds: 40_000_000)
        consumer.cancel()
        _ = await consumer.result
        try await Task.sleep(nanoseconds: 60_000_000)
        let wasCancelled = await observer.cancelled
        XCTAssertTrue(wasCancelled)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testPubMedURLsAreStrictAndDeduplicated() {
        XCTAssertEqual(
            PubMed.url(for: " 38743124 ")?.absoluteString,
            "https://pubmed.ncbi.nlm.nih.gov/38743124/"
        )
        XCTAssertNil(PubMed.url(for: "PMID:38743124"))
        XCTAssertNil(PubMed.url(for: "123/other"))

        let references = [
            LiteratureReference(pmid: "1", title: "A"),
            LiteratureReference(pmid: "1", title: "Duplicate"),
            LiteratureReference(pmid: "2", title: "B"),
        ]
        XCTAssertEqual(PubMed.urls(for: references).map(\.absoluteString), [
            "https://pubmed.ncbi.nlm.nih.gov/1/",
            "https://pubmed.ncbi.nlm.nih.gov/2/",
        ])
        let searchURL = try? XCTUnwrap(PubMed.searchURL(for: references))
        let components = searchURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(
            components?.queryItems?.first(where: { $0.name == "term" })?.value,
            "1 2"
        )
    }

    func testPlainReportContainsAnswerMetadataEvidenceAndDisclaimer() {
        let report = LiteratureReportFormatter.plainText(fixtureResult())
        XCTAssertTrue(report.contains("GLKB citation recommendations (1)"))
        XCTAssertTrue(report.contains("Grounded answer"))
        XCTAssertTrue(report.contains("One, Two, Three, et al. · Journal · 2024"))
        XCTAssertTrue(report.contains("PMID: 42 — https://pubmed.ncbi.nlm.nih.gov/42/"))
        XCTAssertTrue(report.contains("Evidence: “Supporting evidence.”"))
        XCTAssertTrue(report.contains("Verify each source before citing."))
    }

    func testReportsCanOmitEvidenceAndHTMLIsEscaped() {
        var result = fixtureResult()
        result.answer = "Answer <script>alert('x')</script>"
        result.references[0].title = "A & B < C"

        let plain = LiteratureReportFormatter.plainText(result, includeEvidence: false)
        XCTAssertFalse(plain.contains("Supporting evidence"))

        let html = LiteratureReportFormatter.html(result, includeEvidence: false)
        XCTAssertTrue(html.contains("A &amp; B &lt; C"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<blockquote>"))
    }

    private func fixtureResult(answer: String = "Grounded answer") -> LiteratureResult {
        LiteratureResult(
            answer: answer,
            references: [
                LiteratureReference(
                    pmid: "42",
                    title: "A relevant article",
                    authors: ["One", "Two", "Three", "Four"],
                    journal: "Journal",
                    date: "2024",
                    citationCount: 7,
                    evidence: [.init(quote: "Supporting evidence.", contextType: "abstract")]
                )
            ]
        )
    }

    private static func completedResult(
        from stream: AsyncThrowingStream<LiteratureQueryEvent, Error>
    ) async throws -> LiteratureResult {
        for try await event in stream {
            if case .completed(let result) = event { return result }
        }
        throw FixtureStreamError.noCompletion
    }
}

private enum FixtureStreamError: Error { case noCompletion }

private final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

private actor AsyncCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor CancellationObserver {
    private(set) var cancelled = false
    func markCancelled() { cancelled = true }
}

/// A slow backend that records whether its request was cancelled.
private struct ObservingBackend: LiteratureBackend {
    let counter: AsyncCounter
    let observer: CancellationObserver
    let result: LiteratureResult

    func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await counter.increment()
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    await observer.markCancelled()
                    continuation.finish(throwing: LiteratureError.cancelled)
                    return
                }
                continuation.yield(.completed(result))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct FixtureBackend: LiteratureBackend {
    let counter: AsyncCounter
    let result: LiteratureResult
    var delayNanoseconds: UInt64 = 0

    func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await counter.increment()
                if delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                continuation.yield(.completed(result))
                continuation.finish()
            }
        }
    }
}
