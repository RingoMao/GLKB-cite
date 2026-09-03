import CryptoKit
import Foundation

public struct LiteratureCacheKey: Hashable, Sendable, CustomStringConvertible {
    public let digest: String

    public var description: String { digest }

    public init(digest: String) {
        self.digest = digest
    }

    public static func make(
        query: LiteratureQuery,
        endpointScope: String,
        credentialScope: String
    ) -> Self {
        let normalizedText = (try? LiteratureInputValidator.normalize(query.text))
            ?? LiteratureNetworking.clean(query.text)
        let options = query.options.normalized
        let components = [
            "glkb-cite-v2",
            normalizedText,
            String(options.maxArticles),
            // GLKB retrieves the same response regardless of this presentation
            // toggle, so changing it must not incur another paid request.
            "presentation-only",
            endpointScope,
            credentialScope,
        ]
        let data = Data(components.joined(separator: "\u{001F}").utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Self(digest: digest)
    }
}

public actor InMemoryLiteratureCache {
    public typealias DateProvider = @Sendable () -> Date

    private struct Entry: Sendable {
        var result: LiteratureResult
        var expiresAt: Date
        var insertionOrder: UInt64
    }

    private var entries: [LiteratureCacheKey: Entry] = [:]
    private var insertionCounter: UInt64 = 0
    private let maximumEntries: Int
    private let now: DateProvider

    public init(maximumEntries: Int = 20, now: @escaping DateProvider = { Date() }) {
        self.maximumEntries = max(1, maximumEntries)
        self.now = now
    }

    public func value(for key: LiteratureCacheKey) -> LiteratureResult? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now() else {
            entries.removeValue(forKey: key)
            return nil
        }
        var result = entry.result
        result.isCached = true
        return result
    }

    public func insert(_ result: LiteratureResult, for key: LiteratureCacheKey, minutes: Int) {
        let minutes = min(60, max(0, minutes))
        guard minutes > 0 else { return }
        insertionCounter &+= 1
        var storedResult = result
        storedResult.isCached = false
        entries[key] = Entry(
            result: storedResult,
            expiresAt: now().addingTimeInterval(TimeInterval(minutes * 60)),
            insertionOrder: insertionCounter
        )

        while entries.count > maximumEntries,
              let oldest = entries.min(by: { $0.value.insertionOrder < $1.value.insertionOrder })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    public func removeValue(for key: LiteratureCacheKey) {
        entries.removeValue(forKey: key)
    }

    public func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    public var count: Int { entries.count }
}

/// Shares one paid request among simultaneous callers with an identical opaque
/// cache key. Completed values still obey the user-selected cache duration.
public actor InFlightLiteratureRequests {
    private var tasks: [LiteratureCacheKey: Task<LiteratureResult, Error>] = [:]

    public init() {}

    public func result(
        for key: LiteratureCacheKey,
        operation: @escaping @Sendable () async throws -> LiteratureResult
    ) async throws -> LiteratureResult {
        if let task = tasks[key] { return try await task.value }
        let task = Task { try await operation() }
        tasks[key] = task
        do {
            let result = try await task.value
            tasks.removeValue(forKey: key)
            return result
        } catch {
            tasks.removeValue(forKey: key)
            throw error
        }
    }

    public var count: Int { tasks.count }
}

/// Adds memory-only caching to any backend without exposing query text in cache keys.
public final class CachingLiteratureBackend: LiteratureBackend, @unchecked Sendable {
    private let backend: any LiteratureBackend
    private let cache: InMemoryLiteratureCache
    private let inFlight: InFlightLiteratureRequests
    private let endpointScope: String
    private let credentialScope: String

    public init(
        backend: any LiteratureBackend,
        cache: InMemoryLiteratureCache = .init(),
        inFlight: InFlightLiteratureRequests = .init(),
        endpointScope: String,
        credentialScope: String = "anonymous"
    ) {
        self.backend = backend
        self.cache = cache
        self.inFlight = inFlight
        self.endpointScope = endpointScope
        self.credentialScope = credentialScope
    }

    public func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let options = query.options.normalized
                let key = LiteratureCacheKey.make(
                    query: query,
                    endpointScope: endpointScope,
                    credentialScope: credentialScope
                )
                if options.cacheDurationMinutes > 0, let cached = await cache.value(for: key) {
                    continuation.yield(.completed(cached))
                    continuation.finish()
                    return
                }

                continuation.yield(.progress(step: "Searching GLKB", content: nil))
                do {
                    let result = try await inFlight.result(for: key) { [backend] in
                        for try await event in backend.query(query) {
                            if case .completed(let result) = event { return result }
                        }
                        throw LiteratureError.malformedResponse(
                            "GLKB finished without a completed result."
                        )
                    }
                    if options.cacheDurationMinutes > 0 {
                        await cache.insert(result, for: key, minutes: options.cacheDurationMinutes)
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LiteratureError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
