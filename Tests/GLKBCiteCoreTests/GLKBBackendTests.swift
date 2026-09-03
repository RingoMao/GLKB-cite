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
    }

    private static let state = State()

    static func setHandler(_ handler: @escaping Handler) {
        state.lock.lock()
        state.handler = handler
        state.request = nil
        state.requestBody = nil
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
        state.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
        Self.state.lock.lock()
        Self.state.request = request
        Self.state.requestBody = body
        let handler = Self.state.handler
        Self.state.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
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
