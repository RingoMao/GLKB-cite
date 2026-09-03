import Foundation
import XCTest
@testable import GLKBCiteCore

final class ModelsAndValidationTests: XCTestCase {
    func testSelectionContextCodableRoundTrip() throws {
        let context = SelectionContext(
            selectedText: "Insulin regulates glucose homeostasis.",
            sourceApplicationName: "Preview",
            sourceBundleIdentifier: "com.apple.Preview",
            bounds: ScreenRect(x: 10, y: 20, width: 300, height: 44),
            isEditable: false,
            capturedAt: Date(timeIntervalSince1970: 123)
        )

        let decoded = try JSONDecoder().decode(
            SelectionContext.self,
            from: JSONEncoder().encode(context)
        )
        XCTAssertEqual(decoded, context)
    }

    func testEvidenceAndUsageUseBackendCodingKeys() throws {
        let evidence = LiteratureEvidence(quote: "Direct evidence", contextType: "abstract")
        let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        XCTAssertTrue(evidenceJSON.contains("context_type"))

        let usage = LiteratureUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        let usageJSON = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        XCTAssertTrue(usageJSON.contains("prompt_tokens"))
        XCTAssertTrue(usageJSON.contains("completion_tokens"))
        XCTAssertTrue(usageJSON.contains("total_tokens"))
    }

    func testOptionNormalizationClampsCostControls() {
        let high = LiteratureQueryOptions(maxArticles: 99, cacheDurationMinutes: 900).normalized
        XCTAssertEqual(high.maxArticles, 25)
        XCTAssertEqual(high.cacheDurationMinutes, 60)

        let low = LiteratureQueryOptions(maxArticles: -3, cacheDurationMinutes: -1).normalized
        XCTAssertEqual(low.maxArticles, 1)
        XCTAssertEqual(low.cacheDurationMinutes, 0)
    }

    func testInputNormalizationCollapsesWhitespaceAndEscapedPunctuation() throws {
        let normalized = try LiteratureInputValidator.normalize(
            "  SLC30A8\\,   encodes\n a zinc transporter.  "
        )
        XCTAssertEqual(normalized, "SLC30A8, encodes a zinc transporter.")
    }

    func testInputRejectsShortSelection() {
        do {
            _ = try LiteratureInputValidator.normalize("too short")
            XCTFail("Expected invalidInput")
        } catch let error as LiteratureError {
            XCTAssertEqual(error, .invalidInput(
                "Select a complete scientific sentence (at least 10 characters)."
            ))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInputRejectsMoreThanOneThousandCharacters() {
        do {
            _ = try LiteratureInputValidator.normalize(String(repeating: "a", count: 1_001))
            XCTFail("Expected invalidInput")
        } catch let literatureError as LiteratureError {
            guard case .invalidInput(let message) = literatureError else {
                XCTFail("Expected invalidInput")
                return
            }
            XCTAssertTrue(message.contains("1001"))
            XCTAssertTrue(message.contains("1000"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInputAcceptsExactBounds() throws {
        let minimum = try LiteratureInputValidator.normalize(String(repeating: "a", count: 10))
        let maximum = try LiteratureInputValidator.normalize(String(repeating: "a", count: 1_000))
        XCTAssertEqual(minimum.count, 10)
        XCTAssertEqual(maximum.count, 1_000)
    }
}
