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

    func testPMIDsAreCanonicalizedAndNonPubMedIdentifiersIgnored() throws {
        let data = Data(#"""
        {"status":"ok","references":[
          {"pmid":"0038743124","title":"Padded"},
          {"pmid":"38743124","title":"Duplicate of padded"},
          {"pmid":"\u0663\u0668","title":"Arabic-Indic digits"},
          {"pmid":"\uFF13\uFF18","title":"Fullwidth digits"},
          {"pmid":true,"title":"Boolean"},
          {"pmid":"000","title":"All zeros"},
          {"id":"99","title":"Row id only"},
          {"pmid":1234,"title":"Numeric"},
          {"url":"https://pubmed.ncbi.nlm.nih.gov/0042/","title":"From URL"}
        ]}
        """#.utf8)
        let result = try GLKBResponseParser.parse(data, options: .init(maxArticles: 10))
        XCTAssertEqual(result.references.map(\.pmid), ["38743124", "1234", "42"])
        XCTAssertEqual(result.references.map(\.title), ["Padded", "Numeric", "From URL"])
        XCTAssertEqual(result.references.last?.url?.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/42/")
    }

    func testCitationCountsOutsideThePlausibleRangeAreDropped() throws {
        let data = Data(#"""
        {"status":"ok","references":[
          {"pmid":"1","title":"Huge","n_citation":1.5e20},
          {"pmid":"2","title":"Negative","n_citation":-3},
          {"pmid":"3","title":"Boolean","n_citation":true},
          {"pmid":"4","title":"String","n_citation":"7"},
          {"pmid":"5","title":"Whole double","n_citation":12.0},
          {"pmid":"6","title":"Fraction","n_citation":12.5},
          {"pmid":"7","title":"Above cap","n_citation":10000001},
          {"pmid":"8","title":"Null then legacy","n_citation":null,"citation_count":5},
          {"pmid":"9","title":"Thirty digits","n_citation":123456789012345678901234567890}
        ]}
        """#.utf8)
        let result = try GLKBResponseParser.parse(data, options: .init(maxArticles: 10))
        XCTAssertEqual(result.references.map(\.citationCount), [nil, nil, nil, 7, 12, nil, nil, 5, nil])
    }

    func testReferencesContainerShapesAreValidated() {
        XCTAssertThrowsError(try GLKBResponseParser.parse(Data(#"{"status":"ok","references":{"pmid":"1"}}"#.utf8)))
        XCTAssertThrowsError(try GLKBResponseParser.parse(Data(#"{"status":"ok","references":null}"#.utf8)))
        XCTAssertThrowsError(try GLKBResponseParser.parse(
            Data(#"{"status":"no_results","references":[{"pmid":"1","title":"Contradiction"}]}"#.utf8)
        ))
        // Boolean titles are not text.
        XCTAssertThrowsError(try GLKBResponseParser.parse(Data(#"{"status":"ok","references":[{"pmid":"1","title":true}]}"#.utf8)))
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
