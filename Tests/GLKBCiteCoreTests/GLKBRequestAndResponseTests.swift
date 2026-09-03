import Foundation
import XCTest
@testable import GLKBCiteCore

final class GLKBRequestAndResponseTests: XCTestCase {
    func testRequestBuilderUsesOnlyCitationEndpointFields() throws {
        let selected = "Loss-of-function mutations in PCSK9 lower LDL cholesterol."
        let request = try GLKBRequestBuilder.make(
            selectedText: selected,
            options: LiteratureQueryOptions(
                maxArticles: 10,
                includeEvidence: true,
                cacheDurationMinutes: 15
            )
        )

        XCTAssertEqual(request.text, selected)
        XCTAssertEqual(request.maxReferences, 10)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(Set(encoded?.keys.map { $0 } ?? []), Set(["text", "max_references"]))
        XCTAssertEqual(encoded?["text"] as? String, selected)
        XCTAssertEqual(encoded?["max_references"] as? Int, 10)
    }

    func testDefaultRequestUsesFiveReferences() throws {
        let request = try GLKBRequestBuilder.make(
            selectedText: "A sufficiently complete biomedical scientific claim."
        )
        XCTAssertEqual(request.maxReferences, 5)
    }

    func testResponseParserNormalizesObjectsArraysEvidenceAndDeduplicatesPMIDs() throws {
        let fixture = try TestFixtures.data(named: "glkb-response")

        let result = try GLKBResponseParser.parse(fixture)
        XCTAssertEqual(result.answer, "")
        XCTAssertEqual(result.references.count, 2)
        XCTAssertEqual(result.references[0].pmid, "38743124")
        XCTAssertEqual(result.references[0].date, "2024")
        XCTAssertEqual(result.references[0].citationCount, 12)
        XCTAssertEqual(result.references[0].relevanceReason, "Direct evidence for ZnT8")
        XCTAssertEqual(result.references[0].evidence[0], .init(
            quote: "ZnT8 is an autoantigen.",
            contextType: "abstract"
        ))
        XCTAssertEqual(result.references[1].pmid, "12345678")
        XCTAssertEqual(result.references[1].authors, ["C Author"])
    }

    func testResponseParserGeneratesCanonicalPubMedURL() throws {
        let fixture = #"""
        {"status":"ok", "references":[{
          "pubmedid":"42", "title":"Legacy", "citation_count":"7", "year":"1999",
          "evidence":["A quote"]
        }], "diagnostics":{"elapsed_ms":1250}}
        """#.data(using: .utf8)!

        let result = try GLKBResponseParser.parse(fixture)
        XCTAssertEqual(result.references.first?.url?.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/42/")
        XCTAssertEqual(result.references.first?.citationCount, 7)
        XCTAssertEqual(result.references.first?.date, "1999")
        XCTAssertEqual(result.executionTime, 1.25)
    }

    func testResponseParserAppliesReferenceLimit() throws {
        let references = (1 ... 4).map { ["pmid": "\($0)", "title": "Title \($0)"] }
        let data = try JSONSerialization.data(withJSONObject: ["status": "ok", "references": references])
        let result = try GLKBResponseParser.parse(
            data,
            options: LiteratureQueryOptions(maxArticles: 3)
        )
        XCTAssertEqual(result.references.map(\.pmid), ["1", "2", "3"])
    }

    func testNoReferencesIsAValidGroundedEmptyResult() throws {
        let data = #"{"status":"no_results", "query":"Background sentence.", "references":[]}"#.data(using: .utf8)!
        let result = try GLKBResponseParser.parse(data)
        XCTAssertEqual(result.answer, "GLKB found no supporting references for this sentence.")
        XCTAssertTrue(result.references.isEmpty)
    }

    func testUnsafeReferenceURLFallsBackToCanonicalPubMedURL() throws {
        let data = #"{"status":"ok","references":[{"pmid":"42","title":"Article","url":"javascript:alert(1)"}]}"#.data(using: .utf8)!
        let result = try GLKBResponseParser.parse(data)
        XCTAssertEqual(
            result.references.first?.url?.absoluteString,
            "https://pubmed.ncbi.nlm.nih.gov/42/"
        )
    }

    func testNonNumericPMIDIsNotAcceptedAsAReference() throws {
        let data = #"{"status":"ok","references":[{"pmid":"not-a-pmid","title":"Article","url":"https://example.org/"}]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GLKBResponseParser.parse(data))
    }

    func testMalformedAndApplicationErrorResponsesThrow() {
        do {
            _ = try GLKBResponseParser.parse(Data("[]".utf8))
            XCTFail("Expected malformedResponse")
        } catch let literatureError as LiteratureError {
            guard case .malformedResponse = literatureError else {
                XCTFail("Expected malformedResponse")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertThrowsError(try GLKBResponseParser.parse(Data(#"{"status":"unknown","references":[]}"#.utf8)))
    }
}
