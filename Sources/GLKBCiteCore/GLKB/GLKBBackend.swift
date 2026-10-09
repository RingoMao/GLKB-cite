import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class GLKBBackend: LiteratureBackend, @unchecked Sendable {
    public static let defaultEndpoint = URL(
        string: "https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite"
    )!

    /// Responses above this size are rejected before parsing. A citation
    /// response is a few kilobytes; anything larger is a misbehaving server.
    public static let maximumResponseBytes = 2 * 1_024 * 1_024

    /// Statuses that get exactly one retry (each attempt is billed, and only
    /// a transient upstream failure is worth a second request).
    static let retryableStatuses: Set<Int> = [502, 503, 504]

    public typealias APIKeyProvider = @Sendable () async throws -> String

    private let endpoint: URL
    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider
    private let retryDelayNanoseconds: UInt64
    private let redirectPolicy = RedirectRefusingDelegate()

    public convenience init(
        endpoint: URL = GLKBBackend.defaultEndpoint,
        timeout: TimeInterval = 90,
        apiKeyProvider: @escaping APIKeyProvider
    ) {
        self.init(
            endpoint: endpoint,
            session: LiteratureNetworking.ephemeralSession(timeout: timeout),
            apiKeyProvider: apiKeyProvider
        )
    }

    /// Session injection exists for deterministic URLProtocol-based tests.
    public init(
        endpoint: URL = GLKBBackend.defaultEndpoint,
        session: URLSession,
        retryDelayMilliseconds: UInt64 = 600,
        apiKeyProvider: @escaping APIKeyProvider
    ) {
        self.endpoint = endpoint
        self.session = session
        self.retryDelayNanoseconds = retryDelayMilliseconds * 1_000_000
        self.apiKeyProvider = apiKeyProvider
    }

    public func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(step: "Searching GLKB", content: nil))
                    let result = try await execute(query)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LiteratureError.cancelled)
                } catch let error as LiteratureError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LiteratureError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func execute(_ query: LiteratureQuery) async throws -> LiteratureResult {
        guard endpoint.scheme == "https", let host = endpoint.host, !host.isEmpty else {
            throw LiteratureError.invalidEndpoint
        }

        let rawKey = try await apiKeyProvider()
        guard !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiteratureError.missingCredential
        }
        guard let key = GLKBAPIKeyFormat.normalize(rawKey) else {
            throw LiteratureError.invalidInput(
                "The GLKB API key must begin with glkb_ and contain only letters, digits, - and _ on a single line. Check for a line break copied with the key."
            )
        }

        let payload = try GLKBRequestBuilder.make(selectedText: query.text, options: query.options)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LiteratureError.malformedResponse("Expected an HTTP response.")
            }
            // Redirects are refused by the delegate, so a 3xx arrives here as
            // the final response; and a response must come from the endpoint
            // it was sent to.
            if let finalHost = httpResponse.url?.host, finalHost.lowercased() != host.lowercased() {
                throw LiteratureError.transport("The response came from an unexpected host.")
            }
            if (300 ... 399).contains(httpResponse.statusCode) {
                throw LiteratureError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: "The literature service tried to redirect the request, which GLKB Cite does not follow."
                )
            }
            if Self.retryableStatuses.contains(httpResponse.statusCode), attempt == 1 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: retryDelayNanoseconds + UInt64.random(in: 0 ... retryDelayNanoseconds / 2))
                continue
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw LiteratureError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: Self.failureMessage(for: httpResponse, body: data)
                )
            }
            guard data.count <= Self.maximumResponseBytes else {
                throw LiteratureError.malformedResponse(
                    "The response was unexpectedly large (\(data.count) bytes)."
                )
            }
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.lowercased().contains("json") {
                throw LiteratureError.malformedResponse("Expected JSON but received \(LiteratureNetworking.sanitize(contentType)).")
            }
            return try GLKBResponseParser.parse(data, options: query.options)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request, delegate: redirectPolicy)
        } catch is CancellationError {
            throw LiteratureError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession surfaces task cancellation as URLError.cancelled,
            // not CancellationError.
            throw LiteratureError.cancelled
        } catch {
            throw LiteratureError.transport(error.localizedDescription)
        }
    }

    /// Server error text is surfaced for client errors (where it explains
    /// what to change) but not for server errors, whose bodies are often
    /// stack traces or gateway pages. A 429's Retry-After becomes advice.
    private static func failureMessage(for response: HTTPURLResponse, body: Data) -> String? {
        guard response.statusCode < 500 else { return nil }
        var message = LiteratureNetworking.serverMessage(from: body)
        if response.statusCode == 429,
           let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Int(retryAfter.trimmingCharacters(in: .whitespaces)), seconds > 0 {
            let advice = "Try again in \(seconds) second\(seconds == 1 ? "" : "s")."
            message = message.map { "\(advice) \($0)" } ?? advice
        }
        return message
    }
}

/// Refuses every redirect: the Bearer header is stripped on redirect anyway,
/// so a redirected request can never succeed against GLKB — but it would
/// re-POST the user's selected text to whatever host the redirect names.
private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
