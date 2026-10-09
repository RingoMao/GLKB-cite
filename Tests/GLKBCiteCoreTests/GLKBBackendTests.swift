import Foundation
import Dispatch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GLKBCiteCore

final class GLKBBackendTests: XCTestCase {
    private static let suiteGate = DispatchSemaphore(value: 1)

    override func setUp() {
        super.setUp()
        Self.suiteGate.wait()
        URLProtocolFixture.reset()
    }

    override func tearDown() {
        URLProtocolFixture.reset()
        Self.suiteGate.signal()
        super.tearDown()
    }

    func testBackendSendsAuthenticatedRequestAndReturnsEvents() async throws {
        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"status":"ok", "references":[{"pmid":"42", "title":"Article"}]}"#.utf8))
        }
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_x" }
        )

        let events = try await collect(
            backend.query(.init(
                text: "SLC30A8 has an important role in diabetes."
            ))
        )
        XCTAssertEqual(events.count, 2)
        let first = try XCTUnwrap(events.first)
        guard case .progress(let step, _) = first else {
            XCTFail("Expected progress")
            return
        }
        XCTAssertEqual(step, "Searching GLKB")
        let last = try XCTUnwrap(events.last)
        guard case .completed(let result) = last else {
            XCTFail("Expected result")
            return
        }
        XCTAssertEqual(result.references.first?.pmid, "42")

        let request = try XCTUnwrap(URLProtocolFixture.lastRequest())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer glkb_x")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(URLProtocolFixture.lastRequestBody())
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(Set(json?.keys.map { $0 } ?? []), Set(["text", "max_references"]))
        XCTAssertEqual(json?["max_references"] as? Int, 5)
    }

    func testBackendMapsHTTPErrorWithoutLeakingCredential() async {
        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"detail":"Rate limit reached"}"#.utf8))
        }
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_y" }
        )

        do {
            _ = try await backend.execute(.init(
                text: "A complete biomedical claim for literature search."
            ))
            XCTFail("Expected request failure")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .requestFailed(statusCode: 429, message: "Rate limit reached"))
            XCTAssertFalse(error.localizedDescription.contains("glkb_y"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackendRejectsMissingOrMalformedKeyBeforeNetworkRequest() async {
        let missing = GLKBBackend(
            session: makeFixtureSession(),
            apiKeyProvider: { "  " }
        )
        do {
            _ = try await missing.execute(.init(
                text: "A complete biomedical claim for literature search."
            ))
            XCTFail("Expected missing key")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .missingCredential)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let malformed = GLKBBackend(
            session: makeFixtureSession(),
            apiKeyProvider: { "wrong-prefix" }
        )
        do {
            _ = try await malformed.execute(.init(
                text: "A complete biomedical claim for literature search."
            ))
            XCTFail("Expected invalid key")
        } catch let literatureError as LiteratureError {
            guard case .invalidInput = literatureError else {
                XCTFail("Expected invalidInput")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(URLProtocolFixture.lastRequest())
    }

    func testBackendRejectsNonHTTPSEndpoint() async {
        let backend = GLKBBackend(
            endpoint: URL(string: "http://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_test" }
        )
        do {
            _ = try await backend.execute(.init(
                text: "A complete biomedical claim for citation search."
            ))
            XCTFail("Expected endpoint error")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRedirectsAreRefusedWithoutASecondRequest() async {
        URLProtocolFixture.setHandler { request in
            if request.url?.host == "example.test" {
                let redirect = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 307,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Location": "https://elsewhere.test/collect"]
                )!
                return (redirect, Data())
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"status":"ok","references":[{"pmid":"1","title":"Hijacked"}]}"#.utf8))
        }
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_z" }
        )

        do {
            _ = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
            XCTFail("Expected the redirect to be refused")
        } catch let error as LiteratureError {
            guard case .requestFailed(let status, let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(status, 307)
            XCTAssertEqual(message?.contains("redirect"), true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // The selected text was never re-POSTed to the redirect target.
        XCTAssertEqual(URLProtocolFixture.requestCount(), 1)
        XCTAssertEqual(URLProtocolFixture.lastRequest()?.url?.host, "example.test")
    }

    func testTransientGatewayFailureIsRetriedExactlyOnce() async throws {
        URLProtocolFixture.setHandler { request in
            if URLProtocolFixture.requestCount() == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=utf-8"]
            )!
            return (response, Data(#"{"status":"ok","references":[{"pmid":"42","title":"Article"}]}"#.utf8))
        }
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            retryDelayMilliseconds: 1,
            apiKeyProvider: { "glkb_x" }
        )
        let result = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
        XCTAssertEqual(result.references.first?.pmid, "42")
        XCTAssertEqual(URLProtocolFixture.requestCount(), 2)

        URLProtocolFixture.setHandler { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
             Data("<html>gateway stack trace</html>".utf8))
        }
        do {
            _ = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
            XCTFail("Expected a 503")
        } catch let error as LiteratureError {
            // Server-error bodies are never shown to the user.
            XCTAssertEqual(error, .requestFailed(statusCode: 503, message: nil))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(URLProtocolFixture.requestCount(), 2)
    }

    func testRateLimitAdviceUsesRetryAfter() async {
        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "30"]
            )!
            return (response, Data(#"{"detail":"Rate limit reached"}"#.utf8))
        }
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_y" }
        )
        do {
            _ = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
            XCTFail("Expected rate limiting")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .requestFailed(statusCode: 429, message: "Try again in 30 seconds. Rate limit reached"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonJSONOrOversizedSuccessBodiesAreRejected() async {
        let backend = GLKBBackend(
            endpoint: URL(string: "https://example.test/cite")!,
            session: makeFixtureSession(),
            apiKeyProvider: { "glkb_y" }
        )
        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, Data("<html>captive portal</html>".utf8))
        }
        do {
            _ = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
            XCTFail("Expected malformedResponse")
        } catch let error as LiteratureError {
            guard case .malformedResponse(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("text/html"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        URLProtocolFixture.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(count: GLKBBackend.maximumResponseBytes + 1))
        }
        do {
            _ = try await backend.execute(.init(text: "A complete biomedical claim for literature search."))
            XCTFail("Expected malformedResponse")
        } catch let error as LiteratureError {
            guard case .malformedResponse(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("large"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerMessagesAreBoundedAndPrintable() {
        let long = String(repeating: "x", count: 500)
        let body = Data(#"{"detail":"bad\u0007 request\u001b[31m  \n"# .utf8) + Data(long.utf8) + Data(#""}"#.utf8)
        let message = LiteratureNetworking.serverMessage(from: body)
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.count, LiteratureNetworking.maximumServerMessageLength)
        XCTAssertEqual(message?.hasPrefix("bad request[31m x"), true, message ?? "")
        XCTAssertFalse(message?.unicodeScalars.contains { $0.properties.generalCategory == .control } ?? true)
        XCTAssertEqual(message?.hasSuffix("…"), true)

        let validation = Data(#"{"detail":[{"msg":"too short"},{"msg":"\u0000bad"}]}"#.utf8)
        XCTAssertEqual(LiteratureNetworking.serverMessage(from: validation), "too short; bad")
    }

    private func collect(
        _ stream: AsyncThrowingStream<LiteratureQueryEvent, Error>
    ) async throws -> [LiteratureQueryEvent] {
        var events: [LiteratureQueryEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func makeFixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolFixture.self]
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolFixture: URLProtocol, @unchecked Sendable {
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
