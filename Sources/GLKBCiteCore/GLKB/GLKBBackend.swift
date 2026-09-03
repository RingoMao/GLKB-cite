import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class GLKBBackend: LiteratureBackend, @unchecked Sendable {
    public static let defaultEndpoint = URL(
        string: "https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite"
    )!

    public typealias APIKeyProvider = @Sendable () async throws -> String

    private let endpoint: URL
    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider

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
        apiKeyProvider: @escaping APIKeyProvider
    ) {
        self.endpoint = endpoint
        self.session = session
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
        guard endpoint.scheme == "https", endpoint.host != nil else {
            throw LiteratureError.invalidEndpoint
        }

        let key = try await apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LiteratureError.missingCredential }
        guard key.hasPrefix("glkb_") else {
            throw LiteratureError.invalidInput("The GLKB API key must begin with glkb_.")
        }

        let payload = try GLKBRequestBuilder.make(selectedText: query.text, options: query.options)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw LiteratureError.cancelled
        } catch {
            throw LiteratureError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiteratureError.malformedResponse("Expected an HTTP response.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw LiteratureError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: LiteratureNetworking.serverMessage(from: data)
            )
        }
        return try GLKBResponseParser.parse(data, options: query.options)
    }
}
