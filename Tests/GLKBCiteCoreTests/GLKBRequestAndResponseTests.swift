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

    func testResponseParserReadsOptionalLocatorFields() throws {
        let data = Data(#"""
        {"status":"ok","references":[
          {"pmid":"38128529","title":"Disrupted RNA editing","journal":"Cell metabolism","date":"2024",
           "doi":"https://doi.org/10.1016/j.cmet.2023.11.011","volume":36,"issue":"1","pages":"48-61.e6"},
          {"pmid":"8100367","title":"Induction of type I diabetes","doi":"not a doi","volume":"","pagination":"1700-3"},
          {"pmid":"2891993","title":"Immunoreactive alpha-interferon"}
        ]}
        """#.utf8)
        let references = try GLKBResponseParser.parse(data).references
        XCTAssertEqual(references[0].doi, "10.1016/j.cmet.2023.11.011")
        XCTAssertEqual(references[0].volume, "36")
        XCTAssertEqual(references[0].issue, "1")
        XCTAssertEqual(references[0].pages, "48-61.e6")
        XCTAssertNil(references[1].doi)
        XCTAssertNil(references[1].volume)
        XCTAssertEqual(references[1].pages, "1700-3")
        XCTAssertNil(references[2].doi)
        XCTAssertNil(references[2].pages)
    }

    func testDOINormalization() {
        XCTAssertEqual(GLKBResponseParser.doi("10.1038/nature12373"), "10.1038/nature12373")
        XCTAssertEqual(GLKBResponseParser.doi("https://doi.org/10.1038/nature12373"), "10.1038/nature12373")
        XCTAssertEqual(GLKBResponseParser.doi("http://dx.doi.org/10.1038/nature12373"), "10.1038/nature12373")
        XCTAssertEqual(GLKBResponseParser.doi("doi: 10.1038/nature12373"), "10.1038/nature12373")
        XCTAssertEqual(GLKBResponseParser.doi("DOI:10.1002/(SICI)1097-0258"), "10.1002/(SICI)1097-0258")
        XCTAssertNil(GLKBResponseParser.doi(""))
        XCTAssertNil(GLKBResponseParser.doi("10.1038"))
        XCTAssertNil(GLKBResponseParser.doi("10.1038/"))
        XCTAssertNil(GLKBResponseParser.doi("PMC1234567"))
        XCTAssertNil(GLKBResponseParser.doi("10.1038/nature 12373"))
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
