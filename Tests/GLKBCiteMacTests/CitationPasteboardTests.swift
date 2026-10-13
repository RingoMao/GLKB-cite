import AppKit
import GLKBCiteCore
import XCTest
@testable import GLKBCiteMac

final class CitationPasteboardTests: XCTestCase {
    private let link = URL(string: "https://pubmed.ncbi.nlm.nih.gov/8100367/")!

    private var citation: FormattedCitation {
        FormattedCitation(runs: [
            .init(text: "Stewart, T. A. (1993). Induction of type I diabetes. "),
            .init(text: "Science", isItalic: true),
            .init(text: ". "),
            .init(text: link.absoluteString, link: link),
        ])
    }

    func testRTFKeepsItalicsAndTheLink() throws {
        let data = try XCTUnwrap(CitationPasteboard.rtfData(for: citation))
        let text = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(text.string, citation.plainText)

        let science = (text.string as NSString).range(of: "Science")
        let font = try XCTUnwrap(text.attribute(.font, at: science.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic))

        let urlRange = (text.string as NSString).range(of: link.absoluteString)
        let stored = text.attribute(.link, at: urlRange.location, effectiveRange: nil)
        XCTAssertEqual((stored as? URL) ?? (stored as? String).flatMap(URL.init(string:)), link)
        XCTAssertNil(text.attribute(.link, at: science.location, effectiveRange: nil))
    }

    func testPasteboardCarriesPlainRTFAndHTML() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("org.glkb.cite.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        CitationPasteboard.write(citation, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), citation.plainText)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
        XCTAssertTrue(pasteboard.string(forType: .html)?.contains("<a href=\"\(link.absoluteString)\">") ?? false)
    }
}
