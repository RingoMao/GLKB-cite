import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches bibliographic details for PubMed identifiers from NCBI's
/// E-utilities. Only the PMIDs leave the Mac: no credential, no selected
/// text. NCBI allows three requests a second without an API key; the app
/// makes one request per Cite modal, for every PMID in the current result.
public final class PubMedArticleService: @unchecked Sendable {
    public static let defaultEndpoint = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")!

    /// A record with its abstract runs to a few tens of kilobytes; a result
    /// never holds more than 25 references.
    public static let maximumResponseBytes = 8 * 1_024 * 1_024
    public static let maximumIdentifiersPerRequest = 50

    /// Identifies the client to NCBI, as its usage policy asks.
    static let toolName = "glkb-cite"

    private let endpoint: URL
    private let session: URLSession
    private let redirectPolicy = RedirectRefusingDelegate()

    public convenience init(endpoint: URL = PubMedArticleService.defaultEndpoint, timeout: TimeInterval = 20) {
        self.init(endpoint: endpoint, session: LiteratureNetworking.ephemeralSession(timeout: timeout))
    }

    /// Session injection exists for deterministic URLProtocol-based tests.
    public init(endpoint: URL = PubMedArticleService.defaultEndpoint, session: URLSession) {
        self.endpoint = endpoint
        self.session = session
    }

    /// The records PubMed holds for `pmids`, keyed by canonical PMID.
    /// Identifiers PubMed does not know are simply absent from the result.
    public func articles(for pmids: [String]) async throws -> [String: ArticleMetadata] {
        var seen = Set<String>()
        let identifiers = pmids.compactMap { PubMed.canonicalPMID($0) }.filter { seen.insert($0).inserted }
        guard !identifiers.isEmpty else { return [:] }
        guard identifiers.count <= Self.maximumIdentifiersPerRequest else {
            throw LiteratureError.invalidInput("At most \(Self.maximumIdentifiersPerRequest) PubMed identifiers can be fetched at once.")
        }
        guard endpoint.scheme == "https", let host = endpoint.host, !host.isEmpty,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { throw LiteratureError.invalidEndpoint }

        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "id", value: identifiers.joined(separator: ",")),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "tool", value: Self.toolName),
        ]
        guard let url = components.url else { throw LiteratureError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml, text/xml", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request, delegate: redirectPolicy)
        } catch is CancellationError {
            throw LiteratureError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw LiteratureError.cancelled
        } catch {
            throw LiteratureError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiteratureError.malformedResponse("Expected an HTTP response from PubMed.")
        }
        if let finalHost = httpResponse.url?.host, finalHost.lowercased() != host.lowercased() {
            throw LiteratureError.transport("The PubMed response came from an unexpected host.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw LiteratureError.requestFailed(statusCode: httpResponse.statusCode, message: nil)
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw LiteratureError.malformedResponse("The PubMed response was unexpectedly large (\(data.count) bytes).")
        }
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           !contentType.lowercased().contains("xml") {
            throw LiteratureError.malformedResponse(
                "Expected XML from PubMed but received \(LiteratureNetworking.sanitize(contentType))."
            )
        }

        var result: [String: ArticleMetadata] = [:]
        for article in try PubMedArticleParser.parse(data) {
            result[article.pmid] = article
        }
        return result
    }
}
