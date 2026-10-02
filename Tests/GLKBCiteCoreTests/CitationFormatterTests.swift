import Foundation
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

    /// GLKB sends initials before the surname; PubMed-style test data above
    /// puts them after. Both must render identically.
    private let liveShape = LiteratureReference(
        pmid: "8028670",
        title: "p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes.",
        authors: ["C Caelles", "A Helmberg", "M Karin"],
        journal: "Nature",
        date: "1994"
    )

    /// Noon on 2 October 2026 in the local time zone, for Harvard's
    /// "Accessed" note.
    private let accessed: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 2
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private func cite(_ reference: LiteratureReference, _ style: CitationFormatter.Style) -> String {
        CitationFormatter.citation(for: reference, style: style, accessDate: accessed)
    }

    private func authors(_ names: [String]) -> LiteratureReference {
        LiteratureReference(pmid: "7", title: "Many authors", authors: names, journal: "J Test", date: "2020")
    }

    // MARK: Styles

    func testMLACitation() {
        XCTAssertEqual(
            cite(reference, .mla),
            "Chen, J., et al. \u{201C}Type I interferon signaling precedes islet autoimmunity.\u{201D} "
                + "Cell Reports Medicine, 2024. PubMed, https://pubmed.ncbi.nlm.nih.gov/38291045/."
        )
    }

    func testAPACitation() {
        XCTAssertEqual(
            cite(reference, .apa),
            "Chen, J., Rodriguez, M., & Patel, S. (2024). Type I interferon signaling precedes islet autoimmunity. "
                + "Cell Reports Medicine. https://pubmed.ncbi.nlm.nih.gov/38291045/"
        )
    }

    func testChicagoCitation() {
        XCTAssertEqual(
            cite(reference, .chicago),
            "Chen, J., M. Rodriguez, and S. Patel. \u{201C}Type I interferon signaling precedes islet autoimmunity.\u{201D} "
                + "Cell Reports Medicine, 2024. https://pubmed.ncbi.nlm.nih.gov/38291045/."
        )
    }

    func testHarvardCitation() {
        XCTAssertEqual(
            cite(reference, .harvard),
            "Chen, J., Rodriguez, M. and Patel, S. (2024) \u{2018}Type I interferon signaling precedes islet autoimmunity\u{2019}, "
                + "Cell Reports Medicine. Available at: https://pubmed.ncbi.nlm.nih.gov/38291045/ (Accessed: 2 October 2026)."
        )
    }

    func testVancouverCitation() {
        XCTAssertEqual(
            cite(reference, .vancouver),
            "Chen J, Rodriguez M, Patel S. Type I interferon signaling precedes islet autoimmunity. "
                + "Cell Reports Medicine. 2024. PMID: 38291045."
        )
    }

    func testHarvardAndAPADiffer() {
        XCTAssertNotEqual(cite(reference, .apa), cite(reference, .harvard))
    }

    // MARK: Author names

    func testInitialsFirstInputIsReordered() {
        XCTAssertTrue(cite(liveShape, .mla).hasPrefix("Caelles, C., et al. \u{201C}p53-dependent"))
        XCTAssertTrue(cite(liveShape, .apa).hasPrefix("Caelles, C., Helmberg, A., & Karin, M. (1994)."))
        XCTAssertTrue(cite(liveShape, .chicago).hasPrefix("Caelles, C., A. Helmberg, and M. Karin. \u{201C}"))
        XCTAssertTrue(cite(liveShape, .harvard).hasPrefix("Caelles, C., Helmberg, A. and Karin, M. (1994) \u{2018}"))
        XCTAssertTrue(cite(liveShape, .vancouver).hasPrefix("Caelles C, Helmberg A, Karin M. p53-dependent"))
    }

    func testTwoAuthorsUseEachStylesConjunction() {
        var pair = reference
        pair.authors = ["Okafor T", "Lindqvist A"]
        XCTAssertTrue(cite(pair, .mla).hasPrefix("Okafor, T., and A. Lindqvist. \u{201C}"))
        XCTAssertTrue(cite(pair, .apa).hasPrefix("Okafor, T., & Lindqvist, A. (2024)."))
        XCTAssertTrue(cite(pair, .chicago).hasPrefix("Okafor, T., and A. Lindqvist. \u{201C}"))
        XCTAssertTrue(cite(pair, .harvard).hasPrefix("Okafor, T. and Lindqvist, A. (2024) \u{2018}"))
        XCTAssertTrue(cite(pair, .vancouver).hasPrefix("Okafor T, Lindqvist A. "))
    }

    func testEtAlThresholdsPerStyle() {
        let names = Array("ABCDEFGHIJKLMNOPQRSTU").map { "\($0) Name\($0)" }

        // MLA: three or more authors → first author et al.
        XCTAssertTrue(cite(authors(Array(names.prefix(3))), .mla).hasPrefix("NameA, A., et al. "))

        // Harvard: up to three listed, four or more → et al.
        XCTAssertTrue(cite(authors(Array(names.prefix(3))), .harvard).hasPrefix("NameA, A., NameB, B. and NameC, C. (2020)"))
        XCTAssertTrue(cite(authors(Array(names.prefix(4))), .harvard).hasPrefix("NameA, A. et al. (2020)"))

        // Vancouver: six listed, then et al.
        let seven = cite(authors(Array(names.prefix(7))), .vancouver)
        XCTAssertTrue(seven.hasPrefix("NameA A, NameB B, NameC C, NameD D, NameE E, NameF F, et al. "))
        XCTAssertFalse(seven.contains("NameG"))

        // Chicago: up to ten listed; more → the first seven and et al.
        XCTAssertTrue(cite(authors(Array(names.prefix(10))), .chicago).contains(", I. NameI, and J. NameJ. "))
        let eleven = cite(authors(Array(names.prefix(11))), .chicago)
        XCTAssertTrue(eleven.contains(", G. NameG, et al. "))
        XCTAssertFalse(eleven.contains("NameH"))

        // APA: up to twenty listed; more → nineteen, an ellipsis, the last.
        XCTAssertTrue(cite(authors(Array(names.prefix(20))), .apa).contains(", NameS, S., & NameT, T. (2020)."))
        let twentyOne = cite(authors(names), .apa)
        XCTAssertTrue(twentyOne.contains(", NameS, S., . . . NameU, U. (2020)."))
        XCTAssertFalse(twentyOne.contains("NameT"))
    }

    func testGroupAuthorsAndSuffixes() {
        var mixed = reference
        mixed.authors = ["WHO Study Group", "Smith J Jr"]
        XCTAssertTrue(cite(mixed, .apa).hasPrefix("WHO Study Group, & Smith, J., Jr. (2024)."))
        XCTAssertTrue(cite(mixed, .mla).hasPrefix("WHO Study Group, and J. Smith Jr. \u{201C}"))
        XCTAssertTrue(cite(mixed, .vancouver).hasPrefix("WHO Study Group, Smith J Jr. "))
        XCTAssertTrue(CitationFormatter.bibtex(for: mixed).contains("author = {{WHO Study Group} and Smith, Jr., J.}"))
        XCTAssertTrue(CitationFormatter.ris(for: mixed).contains("AU  - Smith, J., Jr."))
    }

    func testAuthorNameParsing() {
        func parsed(_ raw: String) -> (String, [String], String?, Bool)? {
            AuthorName.parse(raw).map { ($0.surname, $0.givenNames, $0.suffix, $0.isCorporate) }
        }
        XCTAssertTrue(parsed("Caelles CA")! == ("Caelles", ["CA"], nil, false))
        XCTAssertTrue(parsed("C A Caelles")! == ("Caelles", ["C", "A"], nil, false))
        XCTAssertTrue(parsed("Caelles, Carme")! == ("Caelles", ["Carme"], nil, false))
        XCTAssertTrue(parsed("Carme Caelles")! == ("Caelles", ["Carme"], nil, false))
        XCTAssertTrue(parsed("J van der Berg")! == ("van der Berg", ["J"], nil, false))
        XCTAssertTrue(parsed("van der Berg JA")! == ("van der Berg", ["JA"], nil, false))
        XCTAssertTrue(parsed("Smith, John, Jr.")! == ("Smith", ["John"], "Jr", false))
        XCTAssertTrue(parsed("Anonymous")! == ("Anonymous", [], nil, false))
        XCTAssertTrue(parsed("GBD 2019 Collaborators")! == ("GBD 2019 Collaborators", [], nil, true))
        XCTAssertNil(parsed("   "))

        let hyphenated = AuthorName.parse("Jean-Pierre Dupont")!
        XCTAssertEqual(hyphenated.inverted(fullGivenNames: false), "Dupont, J.-P.")
        XCTAssertEqual(hyphenated.inverted(fullGivenNames: true), "Dupont, Jean-Pierre")
        XCTAssertEqual(hyphenated.vancouver, "Dupont JP")
    }

    // MARK: Titles, dates and missing fields

    func testTitleEndingInQuestionMarkKeepsOneStop() {
        var asked = reference
        asked.title = "Does it work?"
        for style in CitationFormatter.Style.allCases {
            XCTAssertFalse(cite(asked, style).contains("?."), style.rawValue)
        }
        XCTAssertTrue(cite(asked, .mla).contains("\u{201C}Does it work?\u{201D} Cell Reports Medicine, 2024."))
        XCTAssertTrue(cite(asked, .apa).contains("(2024). Does it work? Cell Reports Medicine."))
        XCTAssertTrue(cite(asked, .harvard).contains("\u{2018}Does it work?\u{2019}, Cell Reports Medicine."))
    }

    func testYearIsExtractedFromLongDates() {
        var dated = reference
        dated.date = "2023 Mar 14"
        XCTAssertTrue(cite(dated, .apa).contains("(2023)."))

        dated.date = "14-03-2022"
        XCTAssertTrue(cite(dated, .apa).contains("(2022)."))
    }

    func testMissingDateUsesEachStylesPlaceholder() {
        var undated = reference
        undated.date = nil
        XCTAssertTrue(cite(undated, .apa).contains(" (n.d.). "))
        XCTAssertTrue(cite(undated, .harvard).contains(" (no date) "))
        XCTAssertTrue(cite(undated, .chicago).contains("Cell Reports Medicine, n.d. https://"))
        XCTAssertTrue(cite(undated, .mla).contains("\u{201D} Cell Reports Medicine. PubMed, "))
        XCTAssertTrue(cite(undated, .vancouver).contains(". Cell Reports Medicine. PMID: "))
    }

    func testMissingAuthorsMoveTheTitleFirst() {
        let anonymous = LiteratureReference(pmid: "3", title: "Anonymous editorial.", journal: "Lancet", date: "2019-05-01")
        XCTAssertEqual(
            cite(anonymous, .apa),
            "Anonymous editorial. (2019). Lancet. https://pubmed.ncbi.nlm.nih.gov/3/"
        )
        XCTAssertTrue(cite(anonymous, .mla).hasPrefix("\u{201C}Anonymous editorial.\u{201D} Lancet, 2019. PubMed, "))
        XCTAssertTrue(cite(anonymous, .chicago).hasPrefix("\u{201C}Anonymous editorial.\u{201D} Lancet, 2019. https://"))
        XCTAssertTrue(cite(anonymous, .harvard).hasPrefix("\u{2018}Anonymous editorial\u{2019} (2019) Lancet. Available at: "))
        XCTAssertTrue(cite(anonymous, .vancouver).hasPrefix("Anonymous editorial. Lancet. 2019. PMID: 3."))
    }

    func testMissingFieldsDegradeGracefully() {
        let bare = LiteratureReference(pmid: "999", title: "Bare title")
        XCTAssertEqual(cite(bare, .apa), "Bare title. (n.d.). https://pubmed.ncbi.nlm.nih.gov/999/")
        XCTAssertEqual(cite(bare, .mla), "\u{201C}Bare title.\u{201D} PubMed, https://pubmed.ncbi.nlm.nih.gov/999/.")
        XCTAssertEqual(cite(bare, .vancouver), "Bare title. PMID: 999.")
    }

    // MARK: Exports

    func testBibTeXEntry() {
        let entry = CitationFormatter.bibtex(for: reference)
        XCTAssertTrue(entry.hasPrefix("@article{pmid38291045,"))
        XCTAssertTrue(entry.contains("author = {Chen, J. and Rodriguez, M. and Patel, S.}"))
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
        XCTAssertTrue(lines.contains("AU  - Chen, J."))
        XCTAssertTrue(lines.contains("AU  - Patel, S."))
        XCTAssertTrue(lines.contains("TI  - Type I interferon signaling precedes islet autoimmunity"))
        XCTAssertTrue(lines.contains("T2  - Cell Reports Medicine"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("JO  - ") })
        XCTAssertTrue(lines.contains("PY  - 2024"))
        XCTAssertTrue(lines.contains("AN  - 38291045"))
        XCTAssertTrue(lines.contains("DB  - PubMed"))
        XCTAssertTrue(lines.contains("UR  - https://pubmed.ncbi.nlm.nih.gov/38291045/"))
        XCTAssertEqual(lines.last, "ER  - ")
    }
}
