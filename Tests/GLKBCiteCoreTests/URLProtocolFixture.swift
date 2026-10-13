import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Serves canned HTTP responses to any URLSession whose configuration lists
/// it, and records what was sent. State is global, so test classes that use
/// it run their tests one at a time (see `suiteGate` in each).
final class URLProtocolFixture: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var handler: Handler?
        var request: URLRequest?
        var requestBody: Data?
        var requestCount = 0
    }

    private static let state = State()

    static func setHandler(_ handler: @escaping Handler) {
        state.lock.lock()
        state.handler = handler
        state.request = nil
        state.requestBody = nil
        state.requestCount = 0
        state.lock.unlock()
    }

    static func lastRequest() -> URLRequest? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.request
    }

    static func lastRequestBody() -> Data? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.requestBody
    }

    static func reset() {
        state.lock.lock()
        state.handler = nil
        state.request = nil
        state.requestBody = nil
        state.requestCount = 0
        state.lock.unlock()
    }

    /// Requests started since the last `setHandler`/`reset`.
    static func requestCount() -> Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
        Self.state.lock.lock()
        Self.state.request = request
        Self.state.requestBody = body
        Self.state.requestCount += 1
        let handler = Self.state.handler
        Self.state.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            // Like a real HTTP load, a 3xx with a Location header offers the
            // session a redirect; the session asks the task delegate, which
            // either starts a new load (a second request through this
            // protocol) or lets the 3xx stand as the final response.
            if (300 ... 399).contains(response.statusCode),
               let location = response.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: request.url)?.absoluteURL {
                var redirected = request
                redirected.url = target
                client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension URLProtocolFixture {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolFixture.self]
        return URLSession(configuration: configuration)
    }
}
