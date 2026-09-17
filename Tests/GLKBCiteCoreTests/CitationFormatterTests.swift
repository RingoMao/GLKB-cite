import XCTest
@testable import GLKBCiteCore

final class CitationFormatterTests: XCTestCase {
    private let reference = LiteratureReference(
        pmid: "38291045",
        title: "Type I interferon signaling precedes islet autoimmunity.",
        authors: ["Chen J", "Rodriguez M", "Patel S"],
        journal: "Cell Reports Medicine",
        date: "2024"
    )

    func testMLACitation() {
        XCTAssertEqual(
            CitationFormatter.citation(for: reference, style: .mla),
            "Chen J, et al. \u{201C}Type I interferon signaling precedes islet autoimmunity.\u{201D} "
                + "Cell Reports Medicine 2024. PubMed ID: 38291045."
        )
    }

    func testAPACitation() {
        XCTAssertEqual(
            CitationFormatter.citation(for: reference, style: .apa),
            "Chen J, et al. (2024). Type I interferon signaling precedes islet autoimmunity. "
                + "Cell Reports Medicine. PubMed ID: 38291045."
        )
    }

    func testChicagoCitation() {
        XCTAssertEqual(
            CitationFormatter.citation(for: reference, style: .chicago),
            "Chen J, et al. \u{201C}Type I interferon signaling precedes islet autoimmunity.\u{201D} "
                + "Cell Reports Medicine (2024). PubMed ID: 38291045."
        )
    }

    func testVancouverListsUpToSixAuthors() {
        let citation = CitationFormatter.citation(for: reference, style: .vancouver)
        XCTAssertEqual(
            citation,
            "Chen J, Rodriguez M, Patel S. Type I interferon signaling precedes islet autoimmunity. "
                + "Cell Reports Medicine. 2024. PubMed ID: 38291045."
        )

        var crowded = reference
        crowded.authors = (1...8).map { "Author \($0)" }
        XCTAssertTrue(
            CitationFormatter.citation(for: crowded, style: .vancouver)
                .contains("Author 6, et al.")
        )
    }

    func testTwoAuthorsAreBothNamed() {
        var pair = reference
        pair.authors = ["Okafor T", "Lindqvist A"]
        XCTAssertTrue(
            CitationFormatter.citation(for: pair, style: .apa)
                .hasPrefix("Okafor T, Lindqvist A. (2024).")
        )
    }

    func testYearIsExtractedFromLongDates() {
        var dated = reference
        dated.date = "2023 Mar 14"
        XCTAssertTrue(CitationFormatter.citation(for: dated, style: .apa).contains("(2023)"))

        dated.date = "14-03-2022"
        XCTAssertTrue(CitationFormatter.citation(for: dated, style: .apa).contains("(2022)"))
    }

    func testMissingFieldsDegradeGracefully() {
        let bare = LiteratureReference(pmid: "999", title: "Bare title")
        XCTAssertEqual(
            CitationFormatter.citation(for: bare, style: .apa),
            "Bare title. PubMed ID: 999."
        )
        XCTAssertEqual(
            CitationFormatter.citation(for: bare, style: .mla),
            "\u{201C}Bare title.\u{201D} PubMed ID: 999."
        )
    }

    func testBibTeXEntry() {
        let entry = CitationFormatter.bibtex(for: reference)
        XCTAssertTrue(entry.hasPrefix("@article{pmid38291045,"))
        XCTAssertTrue(entry.contains("author = {Chen J and Rodriguez M and Patel S}"))
        XCTAssertTrue(entry.contains("title = {Type I interferon signaling precedes islet autoimmunity}"))
        XCTAssertTrue(entry.contains("journal = {Cell Reports Medicine}"))
        XCTAssertTrue(entry.contains("year = {2024}"))
        XCTAssertTrue(entry.contains("url = {https://pubmed.ncbi.nlm.nih.gov/38291045/}"))
        XCTAssertTrue(entry.hasSuffix("}"))
    }

    func testBibTeXEscapesBraces() {
        var braced = reference
        braced.title = "Signaling {in} β-cells"
        XCTAssertTrue(
            CitationFormatter.bibtex(for: braced)
                .contains("title = {Signaling \\{in\\} β-cells}")
        )
    }

    func testRISRecord() {
        let record = CitationFormatter.ris(for: reference)
        let lines = record.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "TY  - JOUR")
        XCTAssertTrue(lines.contains("AU  - Chen J"))
        XCTAssertTrue(lines.contains("AU  - Patel S"))
        XCTAssertTrue(lines.contains("TI  - Type I interferon signaling precedes islet autoimmunity"))
        XCTAssertTrue(lines.contains("JO  - Cell Reports Medicine"))
        XCTAssertTrue(lines.contains("PY  - 2024"))
        XCTAssertTrue(lines.contains("AN  - 38291045"))
        XCTAssertEqual(lines.last, "ER  - ")
    }
}
