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

    func testAuthorNameParsing() throws {
        func parsed(_ raw: String) throws -> (String, [String], String?, Bool) {
            let name = try XCTUnwrap(AuthorName.parse(raw), raw)
            return (name.surname, name.givenNames, name.suffix, name.isCorporate)
        }
        XCTAssertTrue(try parsed("Caelles CA") == ("Caelles", ["CA"], nil, false))
        XCTAssertTrue(try parsed("C A Caelles") == ("Caelles", ["C", "A"], nil, false))
        XCTAssertTrue(try parsed("Caelles, Carme") == ("Caelles", ["Carme"], nil, false))
        XCTAssertTrue(try parsed("Carme Caelles") == ("Caelles", ["Carme"], nil, false))
        XCTAssertTrue(try parsed("J van der Berg") == ("van der Berg", ["J"], nil, false))
        XCTAssertTrue(try parsed("van der Berg JA") == ("van der Berg", ["JA"], nil, false))
        XCTAssertTrue(try parsed("Ludwig Van Beethoven") == ("Van Beethoven", ["Ludwig"], nil, false))
        XCTAssertTrue(try parsed("J Y Lee") == ("Lee", ["J", "Y"], nil, false))
        XCTAssertTrue(try parsed("M Garcia Lopez") == ("Garcia Lopez", ["M"], nil, false))
        XCTAssertTrue(try parsed("Smith, John, Jr.") == ("Smith", ["John"], "Jr", false))
        XCTAssertTrue(try parsed("Smith, Jr.") == ("Smith", [], "Jr", false))
        XCTAssertTrue(try parsed("Smith III") == ("Smith", [], "III", false))
        XCTAssertTrue(try parsed("Smith J 2nd") == ("Smith", ["J"], "2nd", false))
        XCTAssertTrue(try parsed("Ivanov IV") == ("Ivanov", ["IV"], nil, false))
        XCTAssertTrue(try parsed("Anonymous") == ("Anonymous", [], nil, false))
        XCTAssertTrue(try parsed("GBD 2019 Collaborators") == ("GBD 2019 Collaborators", [], nil, true))
        XCTAssertTrue(try parsed("Study Group") == ("Study Group", [], nil, true))
        XCTAssertTrue(try parsed("Study A") == ("Study", ["A"], nil, false))
        XCTAssertTrue(try parsed("A Study") == ("Study", ["A"], nil, false))
        XCTAssertNil(AuthorName.parse("   "))

        let hyphenated = try XCTUnwrap(AuthorName.parse("Jean-Pierre Dupont"))
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

    // MARK: Italics

    func testJournalTitlesAreItalicWhereStylesRequire() {
        for style in [CitationFormatter.Style.mla, .apa, .chicago, .harvard] {
            let formatted = CitationFormatter.formattedCitation(for: reference, style: style, accessDate: accessed)
            XCTAssertEqual(formatted.plainText, cite(reference, style), style.rawValue)
            XCTAssertTrue(formatted.runs.contains { $0.isItalic && $0.text == "Cell Reports Medicine" }, style.rawValue)
            XCTAssertFalse(formatted.runs.contains { $0.isItalic && $0.text.contains("Type I interferon") }, style.rawValue)
        }
        let vancouver = CitationFormatter.formattedCitation(for: reference, style: .vancouver, accessDate: accessed)
        XCTAssertFalse(vancouver.runs.contains(where: \.isItalic))
        XCTAssertEqual(vancouver.plainText, cite(reference, .vancouver))
    }

    func testMLAItalicisesTheDatabaseName() {
        let mla = CitationFormatter.formattedCitation(for: reference, style: .mla, accessDate: accessed)
        XCTAssertTrue(mla.runs.contains { $0.isItalic && $0.text == "PubMed" })
        XCTAssertTrue(mla.html.hasSuffix(
            "<i>Cell Reports Medicine</i>, 2024. <i>PubMed</i>, https://pubmed.ncbi.nlm.nih.gov/38291045/."
        ))
    }

    func testFormattedCitationRenderings() {
        let apa = CitationFormatter.formattedCitation(for: reference, style: .apa, accessDate: accessed)
        XCTAssertTrue(apa.html.contains("Type I interferon signaling precedes islet autoimmunity. <i>Cell Reports Medicine</i>. https://"))
        XCTAssertEqual(String(apa.attributedString.characters), apa.plainText)
        let italicRuns = apa.attributedString.runs
            .filter { $0.inlinePresentationIntent == .emphasized }
            .map { String(apa.attributedString[$0.range].characters) }
        XCTAssertEqual(italicRuns, ["Cell Reports Medicine"])

        var ampersand = reference
        ampersand.journal = "Science & Medicine"
        XCTAssertTrue(
            CitationFormatter.formattedCitation(for: ampersand, style: .harvard, accessDate: accessed).html
                .contains("<i>Science &amp; Medicine</i>")
        )

        let merged = FormattedCitation(runs: [.init(text: "a"), .init(text: ""), .init(text: "b"), .init(text: "c", isItalic: true)])
        XCTAssertEqual(merged.runs, [.init(text: "ab"), .init(text: "c", isItalic: true)])
    }

    // MARK: Exports

    func testBibTeXEntry() {
        let entry = CitationFormatter.bibtex(for: reference)
        XCTAssertTrue(entry.hasPrefix("@article{pmid38291045,"))
        XCTAssertTrue(entry.contains("author = {Chen, J. and Rodriguez, M. and Patel, S.}"))
        XCTAssertTrue(entry.contains("title = {{Type I interferon signaling precedes islet autoimmunity}}"))
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
                .contains("title = {{Signaling \\{in\\} β-cells}}")
        )
    }

    func testRISRecord() {
        let record = CitationFormatter.ris(for: reference)
        XCTAssertTrue(record.hasSuffix("ER  - \r\n"))
        XCTAssertFalse(record.contains("\r\n\r\n"))
        let lines = record.components(separatedBy: "\r\n").dropLast()
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

    func testBibTeXEscapesEveryTeXSpecialCharacterOnce() {
        var special = reference
        special.title = ##"Cost & benefit: 5% of H_2O at #1 ~ ^ $x$ \ back"##
        special.journal = "J {Odd} & Co"
        let entry = CitationFormatter.bibtex(for: special)
        XCTAssertTrue(entry.contains(
            ##"title = {{Cost \& benefit: 5\% of H\_2O at \#1 \textasciitilde{} \textasciicircum{} \$x\$ \textbackslash{} back}}"##
        ), entry)
        XCTAssertTrue(entry.contains(##"journal = {J \{Odd\} \& Co}"##))
        // A single pass never re-escapes its own output.
        XCTAssertFalse(entry.contains("textbackslash\\{"))
        XCTAssertTrue(entry.contains("url = {https://pubmed.ncbi.nlm.nih.gov/38291045/}"))
    }

    func testBibTeXKeyAndLocatorsForNonPubMedIdentifiers() {
        let odd = LiteratureReference(
            pmid: "doi:10.1/x y}",
            title: "Odd identifier",
            url: URL(string: "https://example.org/a")
        )
        let entry = CitationFormatter.bibtex(for: odd)
        XCTAssertTrue(entry.hasPrefix("@article{glkb-doi101xy,"), entry)
        XCTAssertFalse(entry.contains("pmid = "))
        XCTAssertTrue(entry.contains("url = {https://example.org/a}"))
        // MLA names the database only for a PubMed locator.
        XCTAssertEqual(cite(odd, .mla), "\u{201C}Odd identifier.\u{201D} https://example.org/a.")
        XCTAssertEqual(cite(odd, .vancouver), "Odd identifier.")
        XCTAssertFalse(CitationFormatter.ris(for: odd).contains("AN  - "))

        var unsafe = odd
        unsafe.url = URL(string: "javascript:alert(1)")
        XCTAssertEqual(cite(unsafe, .apa), "Odd identifier. (n.d.).")
    }

    func testLeadingZeroAndUnicodeDigitPMIDs() {
        var padded = reference
        padded.pmid = "0038291045"
        XCTAssertTrue(cite(padded, .vancouver).hasSuffix("PMID: 38291045."))
        XCTAssertTrue(CitationFormatter.bibtex(for: padded).hasPrefix("@article{pmid38291045,"))

        var arabic = reference
        arabic.pmid = "\u{0663}\u{0668}"
        XCTAssertFalse(cite(arabic, .vancouver).contains("PMID"))
        XCTAssertFalse(cite(arabic, .mla).contains("pubmed.ncbi"))
    }

    func testMissingTitleUsesPlaceholder() {
        var untitled = reference
        untitled.title = " . "
        XCTAssertTrue(cite(untitled, .apa).contains("(2024). [Untitled]. Cell Reports Medicine."))
        XCTAssertTrue(CitationFormatter.bibtex(for: untitled).contains("title = {{[Untitled]}}"))
        XCTAssertTrue(CitationFormatter.ris(for: untitled).contains("TI  - [Untitled]\r\n"))
    }

    func testYearRequiresFourPlausibleASCIIDigits() {
        XCTAssertEqual(CitationFormatter.year(from: "2024 Mar 14"), "2024")
        XCTAssertEqual(CitationFormatter.year(from: "14-03-2022"), "2022")
        XCTAssertEqual(CitationFormatter.year(from: "20240312"), "2024")
        XCTAssertEqual(CitationFormatter.year(from: "vol 123, 2019"), "2019")
        XCTAssertEqual(CitationFormatter.year(from: "9999"), "")
        XCTAssertEqual(CitationFormatter.year(from: "0000-01-01"), "")
        XCTAssertEqual(CitationFormatter.year(from: "12345"), "")
        XCTAssertEqual(CitationFormatter.year(from: "\u{0662}\u{0660}\u{0662}\u{0664}"), "")
        XCTAssertEqual(CitationFormatter.year(from: "\u{00B2}\u{00B3}\u{00B9}\u{2074}"), "")
        XCTAssertEqual(CitationFormatter.year(from: nil), "")
    }

    func testStyleLongNamesNameTheEdition() {
        XCTAssertEqual(CitationFormatter.Style.chicago.longName, "Chicago 17 (notes-bibliography)")
        for style in CitationFormatter.Style.allCases {
            XCTAssertTrue(style.longName.hasPrefix(style.rawValue), style.rawValue)
        }
    }

    // MARK: With PubMed's record

    /// PubMed's record for PMID 8028670, as efetch returns it.
    private var natureArticle: ArticleMetadata {
        ArticleMetadata(
            pmid: "8028670",
            title: "p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes.",
            authors: [
                ArticleAuthor(lastName: "Caelles", foreName: "C", initials: "C"),
                ArticleAuthor(lastName: "Helmberg", foreName: "A", initials: "A"),
                ArticleAuthor(lastName: "Karin", foreName: "M", initials: "M"),
            ],
            journalTitle: "Nature", journalAbbreviation: "Nature",
            year: "1994", month: "Jul", day: "21", volume: "370", issue: "6486",
            pages: "220-3", doi: "10.1038/370220a0"
        )
    }

    /// GLKB's view of the same article, with PubMed's record attached.
    private var nature: LiteratureReference {
        LiteratureReference(
            pmid: "8028670", title: "p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes",
            authors: ["C Caelles", "A Helmberg", "M Karin"], journal: "Nature", date: "1994",
            article: natureArticle
        )
    }

    private var sciRep: LiteratureReference {
        LiteratureReference(
            pmid: "38291045", title: "Effect of interferon therapy on quality of life in patients with chronic hepatitis B.",
            authors: ["M Zhang", "M Wan", "W Wang", "S Lin"], journal: "Sci Rep", date: "2024",
            article: ArticleMetadata(
                pmid: "38291045",
                title: "Effect of interferon therapy on quality of life in patients with chronic hepatitis B.",
                authors: [
                    ArticleAuthor(lastName: "Zhang", foreName: "Mengdi", initials: "M"),
                    ArticleAuthor(lastName: "Wan", foreName: "Meijuan", initials: "M"),
                    ArticleAuthor(lastName: "Wang", foreName: "Wen", initials: "W"),
                    ArticleAuthor(lastName: "Lin", foreName: "Shumei", initials: "S"),
                ],
                journalTitle: "Scientific reports", journalAbbreviation: "Sci Rep",
                year: "2024", month: "Jan", day: "30", volume: "14", issue: "1",
                pages: "2461", doi: "10.1038/s41598-024-51292-4"
            )
        )
    }

    func testEveryStyleUsesVolumeIssuePagesAndDOIFromPubMed() {
        let title = "p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes"
        XCTAssertEqual(
            cite(nature, .mla),
            "Caelles, C., et al. \u{201C}\(title).\u{201D} Nature, vol. 370, no. 6486, 1994, pp. 220\u{2013}23, https://doi.org/10.1038/370220a0."
        )
        XCTAssertEqual(
            cite(nature, .apa),
            "Caelles, C., Helmberg, A., & Karin, M. (1994). \(title). Nature, 370(6486), 220\u{2013}223. https://doi.org/10.1038/370220a0"
        )
        XCTAssertEqual(
            cite(nature, .chicago),
            "Caelles, C., A. Helmberg, and M. Karin. \u{201C}\(title).\u{201D} Nature 370, no. 6486 (1994): 220\u{2013}23. https://doi.org/10.1038/370220a0."
        )
        XCTAssertEqual(
            cite(nature, .harvard),
            "Caelles, C., Helmberg, A. and Karin, M. (1994) \u{2018}\(title)\u{2019}, Nature, 370(6486), pp. 220\u{2013}223. "
                + "Available at: https://doi.org/10.1038/370220a0 (Accessed: 2 October 2026)."
        )
        XCTAssertEqual(
            cite(nature, .vancouver),
            "Caelles C, Helmberg A, Karin M. \(title). Nature. 1994 Jul 21;370(6486):220-3. doi: 10.1038/370220a0. PMID: 8028670."
        )
    }

    func testItalicsCoverJournalsAndAPAVolumesWithPubMedData() {
        let apa = CitationFormatter.formattedCitation(for: nature, style: .apa, accessDate: accessed)
        XCTAssertTrue(apa.html.hasSuffix("<i>Nature</i>, <i>370</i>(6486), 220\u{2013}223. https://doi.org/10.1038/370220a0"), apa.html)
        let mla = CitationFormatter.formattedCitation(for: nature, style: .mla, accessDate: accessed)
        XCTAssertTrue(mla.html.contains("<i>Nature</i>, vol. 370, no. 6486, 1994, pp. 220\u{2013}23, https://doi.org/"), mla.html)
        XCTAssertFalse(mla.runs.contains { $0.isItalic && $0.text == "PubMed" }, "the DOI replaces the database container")
        let chicago = CitationFormatter.formattedCitation(for: nature, style: .chicago, accessDate: accessed)
        XCTAssertTrue(chicago.html.contains("<i>Nature</i> 370, no. 6486 (1994): 220\u{2013}23."), chicago.html)
        let harvard = CitationFormatter.formattedCitation(for: nature, style: .harvard, accessDate: accessed)
        XCTAssertTrue(harvard.html.contains("<i>Nature</i>, 370(6486), pp. 220\u{2013}223."), harvard.html)
        let vancouver = CitationFormatter.formattedCitation(for: nature, style: .vancouver, accessDate: accessed)
        XCTAssertFalse(vancouver.runs.contains(where: \.isItalic))
    }

    func testFullForenamesJournalCaseAndArticleNumbers() {
        let title = "Effect of interferon therapy on quality of life in patients with chronic hepatitis B"
        XCTAssertEqual(
            cite(sciRep, .mla),
            "Zhang, Mengdi, et al. \u{201C}\(title).\u{201D} Scientific Reports, vol. 14, no. 1, 2024, p. 2461, https://doi.org/10.1038/s41598-024-51292-4."
        )
        XCTAssertEqual(
            cite(sciRep, .apa),
            "Zhang, M., Wan, M., Wang, W., & Lin, S. (2024). \(title). Scientific Reports, 14(1), 2461. https://doi.org/10.1038/s41598-024-51292-4"
        )
        XCTAssertTrue(cite(sciRep, .chicago).hasPrefix("Zhang, Mengdi, Meijuan Wan, Wen Wang, and Shumei Lin. \u{201C}"))
        XCTAssertTrue(cite(sciRep, .chicago).contains("\u{201D} Scientific Reports 14, no. 1 (2024): 2461. https://doi.org/"))
        XCTAssertTrue(cite(sciRep, .harvard).contains("(2024) \u{2018}\(title)\u{2019}, Scientific Reports, 14(1), p. 2461. Available at: https://doi.org/"))
        XCTAssertEqual(
            cite(sciRep, .vancouver),
            "Zhang M, Wan M, Wang W, Lin S. \(title). Sci Rep. 2024 Jan 30;14(1):2461. doi: 10.1038/s41598-024-51292-4. PMID: 38291045."
        )
    }

    func testExportsCarryPubMedFields() {
        let entry = CitationFormatter.bibtex(for: nature)
        for line in [
            "author = {Caelles, C. and Helmberg, A. and Karin, M.}",
            "journal = {Nature}", "year = {1994}", "month = jul", "volume = {370}", "number = {6486}",
            "pages = {220--223}", "doi = {10.1038/370220a0}", "pmid = {8028670}",
            "url = {https://pubmed.ncbi.nlm.nih.gov/8028670/}",
        ] {
            XCTAssertTrue(entry.contains(line), "missing \(line) in\n\(entry)")
        }
        XCTAssertFalse(entry.contains("month = {"))

        let lines = CitationFormatter.ris(for: sciRep).components(separatedBy: "\r\n")
        for line in [
            "AU  - Zhang, Mengdi", "AU  - Lin, Shumei", "T2  - Scientific Reports", "JO  - Sci Rep",
            "VL  - 14", "IS  - 1", "SP  - 2461", "PY  - 2024", "DA  - 2024/01/30/",
            "DO  - 10.1038/s41598-024-51292-4", "AN  - 38291045", "DB  - PubMed",
        ] {
            XCTAssertTrue(lines.contains(line), "missing \(line)")
        }
        XCTAssertFalse(lines.contains { $0.hasPrefix("EP  - ") })
        let natureLines = CitationFormatter.ris(for: nature).components(separatedBy: "\r\n")
        XCTAssertTrue(natureLines.contains("SP  - 220"))
        XCTAssertTrue(natureLines.contains("EP  - 223"))
        XCTAssertFalse(natureLines.contains("JO  - Nature"), "an abbreviation equal to the title is not repeated")
    }

    func testPubMedRecordWinsOverGLKBFieldsButGLKBFillsGaps() {
        var sparse = nature
        sparse.article = ArticleMetadata(pmid: "8028670", volume: "370", pages: "220-3")
        // No PubMed authors, title or journal: GLKB's remain in use.
        XCTAssertEqual(
            cite(sparse, .apa),
            "Caelles, C., Helmberg, A., & Karin, M. (1994). p53-dependent apoptosis in the absence of transcriptional activation of p53-target genes. "
                + "Nature, 370, 220\u{2013}223. https://pubmed.ncbi.nlm.nih.gov/8028670/"
        )
        XCTAssertTrue(cite(sparse, .vancouver).hasSuffix("Nature. 1994;370:220-3. PMID: 8028670."))

        var corrected = nature
        corrected.title = "Wrong GLKB title"
        corrected.authors = ["Nobody N"]
        XCTAssertTrue(cite(corrected, .apa).hasPrefix("Caelles, C., Helmberg, A., & Karin, M. (1994). p53-dependent"))
    }

    func testPageRangesExpandAndAbbreviateLikeChicago() throws {
        func range(_ medline: String) throws -> PageRange { try XCTUnwrap(PageRange(medline: medline)) }
        XCTAssertEqual(try range("220-3").full, "220\u{2013}223")
        XCTAssertEqual(try range("220-3").abbreviated, "220\u{2013}23")
        XCTAssertEqual(try range("220-3").medline, "220-3")
        XCTAssertEqual(try range("101-8").abbreviated, "101\u{2013}8")
        XCTAssertEqual(try range("1103-4").abbreviated, "1103\u{2013}4")
        XCTAssertEqual(try range("321-28").abbreviated, "321\u{2013}28")
        XCTAssertEqual(try range("498-532").abbreviated, "498\u{2013}532")
        XCTAssertEqual(try range("1087-9").abbreviated, "1087\u{2013}89")
        XCTAssertEqual(try range("11564-615").abbreviated, "11564\u{2013}615")
        XCTAssertEqual(try range("12991-3001").abbreviated, "12991\u{2013}3001")
        XCTAssertEqual(try range("3-10").abbreviated, "3\u{2013}10")
        XCTAssertEqual(try range("100-104").abbreviated, "100\u{2013}104")
        XCTAssertEqual(try range("110-5").abbreviated, "110\u{2013}15")
        XCTAssertEqual(try range("998-1004").abbreviated, "998\u{2013}1004")
        XCTAssertEqual(try range("S12-S19").full, "S12\u{2013}S19")
        XCTAssertEqual(try range("e101456").full, "e101456")
        XCTAssertFalse(try range("2461").isRange)
        XCTAssertEqual(try range("220-3; discussion 230-5").full, "220\u{2013}223")
        XCTAssertNil(PageRange(medline: "  "))
    }

    func testJournalCaseAndDOINormalisation() {
        XCTAssertEqual(CitationFormatter.journalCase("Scientific reports"), "Scientific Reports")
        XCTAssertEqual(CitationFormatter.journalCase("The Journal of clinical investigation"), "The Journal of Clinical Investigation")
        XCTAssertEqual(CitationFormatter.journalCase("Proceedings of the National Academy of Sciences of the United States of America"),
                       "Proceedings of the National Academy of Sciences of the United States of America")
        XCTAssertEqual(CitationFormatter.journalCase("mAbs"), "mAbs")
        XCTAssertEqual(CitationFormatter.journalCase("BMJ (Clinical research ed.)"), "BMJ (Clinical Research Ed.)")
        XCTAssertEqual(CitationFormatter.journalCase("Cell reports. Medicine"), "Cell Reports. Medicine")
        XCTAssertEqual(CitationFormatter.journalCase("Cell Reports Medicine"), "Cell Reports Medicine")

        XCTAssertEqual(CitationFormatter.normalizedDOI("doi: 10.1038/370220a0"), "10.1038/370220a0")
        XCTAssertEqual(CitationFormatter.normalizedDOI("https://doi.org/10.1038/370220a0"), "10.1038/370220a0")
        XCTAssertEqual(CitationFormatter.normalizedDOI("http://dx.doi.org/10.1/x"), "10.1/x")
        XCTAssertEqual(CitationFormatter.normalizedDOI("not a doi"), "")
        XCTAssertEqual(CitationFormatter.normalizedDOI(nil), "")
    }

    func testStructuredAuthorsRenderInitialsAndSuffixes() throws {
        let author = try XCTUnwrap(AuthorName(article: ArticleAuthor(lastName: "Vu", foreName: "Thi Hong Ha", initials: "TH")))
        XCTAssertEqual(author.inverted(fullGivenNames: false), "Vu, T. H.")
        XCTAssertEqual(author.inverted(fullGivenNames: true), "Vu, Thi Hong Ha")
        XCTAssertEqual(author.vancouver, "Vu TH")

        let junior = try XCTUnwrap(AuthorName(article: ArticleAuthor(lastName: "Smith", foreName: "John", initials: "J", suffix: "Jr")))
        XCTAssertEqual(junior.inverted(fullGivenNames: true), "Smith, John, Jr.")
        XCTAssertEqual(junior.vancouver, "Smith J Jr")

        let group = try XCTUnwrap(AuthorName(article: ArticleAuthor(collectiveName: "GBD 2019 Collaborators")))
        XCTAssertTrue(group.isCorporate)
        XCTAssertNil(AuthorName(article: ArticleAuthor(initials: "X")))
    }

    // MARK: Rare PubMed records

    private var statPearlsChapter: LiteratureReference {
        LiteratureReference(
            pmid: "42777106", title: "Lupus Panniculitis", authors: ["DL Arnold", "MA Blum", "P Shitabata"], journal: "StatPearls", date: "2026",
            article: ArticleMetadata(
                pmid: "42777106", kind: .bookChapter, title: "Lupus Panniculitis",
                authors: [
                    ArticleAuthor(lastName: "Arnold", foreName: "David L.", initials: "DL"),
                    ArticleAuthor(lastName: "Blum", foreName: "Marissa A.", initials: "MA"),
                    ArticleAuthor(lastName: "Shitabata", foreName: "Paul", initials: "P"),
                ],
                year: "2026", month: "01", publicationTypes: ["Study Guide"],
                bookTitle: "StatPearls", publisher: "StatPearls Publishing", publisherLocation: "Treasure Island (FL)",
                bookshelfID: "NBK625053", contributionDate: ArticleDate(year: "2026", month: "9", day: "14")
            )
        )
    }

    func testBookshelfChaptersCiteTheBookPublisherAndChapterURL() {
        let url = "https://www.ncbi.nlm.nih.gov/books/NBK625053/"
        XCTAssertEqual(
            cite(statPearlsChapter, .mla),
            "Arnold, David L., et al. \u{201C}Lupus Panniculitis.\u{201D} StatPearls, StatPearls Publishing, 2026. NCBI Bookshelf, \(url)."
        )
        XCTAssertEqual(
            cite(statPearlsChapter, .apa),
            "Arnold, D. L., Blum, M. A., & Shitabata, P. (2026). Lupus Panniculitis. In StatPearls. StatPearls Publishing. \(url)"
        )
        XCTAssertEqual(
            cite(statPearlsChapter, .chicago),
            "Arnold, David L., Marissa A. Blum, and Paul Shitabata. \u{201C}Lupus Panniculitis.\u{201D} In StatPearls. Treasure Island (FL): StatPearls Publishing, 2026. \(url)."
        )
        XCTAssertEqual(
            cite(statPearlsChapter, .harvard),
            "Arnold, D. L., Blum, M. A. and Shitabata, P. (2026) \u{2018}Lupus Panniculitis\u{2019}, in StatPearls. Treasure Island (FL): StatPearls Publishing. "
                + "Available at: \(url) (Accessed: 2 October 2026)."
        )
        XCTAssertEqual(
            cite(statPearlsChapter, .vancouver),
            "Arnold DL, Blum MA, Shitabata P. Lupus Panniculitis. 2026 Sep 14. In: StatPearls [Internet]. Treasure Island (FL): StatPearls Publishing; 2026 Jan\u{2013}. "
                + "Available from: \(url) PMID: 42777106."
        )
        let formatted = CitationFormatter.formattedCitation(for: statPearlsChapter, style: .mla, accessDate: accessed)
        XCTAssertTrue(formatted.runs.contains { $0.isItalic && $0.text == "StatPearls" })
        XCTAssertTrue(formatted.runs.contains { $0.isItalic && $0.text == "NCBI Bookshelf" })

        let entry = CitationFormatter.bibtex(for: statPearlsChapter)
        XCTAssertTrue(entry.hasPrefix("@incollection{pmid42777106,"))
        for line in ["booktitle = {StatPearls}", "publisher = {StatPearls Publishing}", "address = {Treasure Island (FL)}", "url = {\(url)}"] {
            XCTAssertTrue(entry.contains(line), line)
        }
        XCTAssertFalse(entry.contains("journal = "))
        let ris = CitationFormatter.ris(for: statPearlsChapter).components(separatedBy: "\r\n")
        for line in ["TY  - CHAP", "T2  - StatPearls", "PB  - StatPearls Publishing", "CY  - Treasure Island (FL)", "UR  - \(url)"] {
            XCTAssertTrue(ris.contains(line), line)
        }
    }

    func testEditedBooksNameTheirEditorsInEachStyle() {
        var chapter = statPearlsChapter
        chapter.article?.bookTitle = "GeneReviews\u{AE}"
        chapter.article?.editors = [
            ArticleAuthor(lastName: "Adam", foreName: "Margaret P", initials: "MP"),
            ArticleAuthor(lastName: "Feldman", foreName: "Jerry", initials: "J"),
            ArticleAuthor(lastName: "Mirzaa", foreName: "Ghayda M", initials: "GM"),
        ]
        XCTAssertTrue(cite(chapter, .mla).contains("GeneReviews\u{AE}, edited by Margaret P. Adam et al., StatPearls Publishing, 2026."))
        XCTAssertTrue(cite(chapter, .apa).contains("In M. P. Adam, J. Feldman, & G. M. Mirzaa (Eds.), GeneReviews\u{AE}. StatPearls Publishing."))
        XCTAssertTrue(cite(chapter, .chicago).contains("In GeneReviews\u{AE}, edited by Margaret P. Adam, Jerry Feldman, and Ghayda M. Mirzaa. Treasure Island (FL):"))
        XCTAssertTrue(cite(chapter, .harvard).contains(", in Adam, M. P., Feldman, J. and Mirzaa, G. M. (eds) GeneReviews\u{AE}. Treasure Island (FL):"))
        XCTAssertTrue(cite(chapter, .vancouver).contains("In: Adam MP, Feldman J, Mirzaa GM, editors. GeneReviews\u{AE} [Internet]."))
        XCTAssertTrue(CitationFormatter.bibtex(for: chapter).contains("editor = {Adam, Margaret P. and Feldman, Jerry and Mirzaa, Ghayda M.}"))
        XCTAssertTrue(CitationFormatter.ris(for: chapter).contains("A2  - Feldman, Jerry\r\n"))

        chapter.article?.editors.removeLast(2)
        XCTAssertTrue(cite(chapter, .apa).contains("In M. P. Adam (Ed.), "))
        XCTAssertTrue(cite(chapter, .harvard).contains("in Adam, M. P. (ed.) "))
        XCTAssertTrue(cite(chapter, .vancouver).contains("In: Adam MP, editor. "))
    }

    func testArticleNumbersIdentifiersSeasonsAndQualifiers() {
        var elife = sciRep
        elife.article = ArticleMetadata(
            pmid: "38206862", title: "Binding and sequestration of poison frog alkaloids by a plasma globulin.",
            authors: [ArticleAuthor(lastName: "Alvarez-Buylla", foreName: "Aurora", initials: "A")],
            journalTitle: "eLife", journalAbbreviation: "Elife", year: "2023", month: "Dec", day: "19", volume: "12",
            articleNumber: "e85096", doi: "10.7554/eLife.85096"
        )
        elife.pmid = "38206862"
        XCTAssertTrue(cite(elife, .apa).contains(". eLife, 12, Article e85096. https://doi.org/10.7554/eLife.85096"), cite(elife, .apa))
        XCTAssertTrue(cite(elife, .mla).contains("eLife, vol. 12, 2023, p. e85096, https://doi.org/"))
        XCTAssertTrue(cite(elife, .chicago).contains("eLife 12 (2023): e85096."))
        XCTAssertTrue(cite(elife, .harvard).contains("eLife, 12, p. e85096."))
        XCTAssertTrue(cite(elife, .vancouver).hasSuffix("Elife. 2023 Dec 19;12:e85096. doi: 10.7554/eLife.85096. PMID: 38206862."))

        var plos = elife
        plos.article?.pages = "e0261090"
        plos.article?.articleNumber = nil
        XCTAssertTrue(cite(plos, .apa).contains(", 12, Article e0261090."))

        var preprint = elife
        preprint.pmid = "42859506"
        preprint.article = ArticleMetadata(
            pmid: "42859506", title: "Broken scale symmetries in undercomplete linear autoencoders.",
            authors: [ArticleAuthor(lastName: "Pashakhanloo", foreName: "Farhad", initials: "F")],
            journalTitle: "ArXiv", journalAbbreviation: "ArXiv", year: "2026", month: "Oct", day: "02",
            articleNumber: "arXiv:2610.03640v1", publicationTypes: ["Journal Article", "Preprint"]
        )
        XCTAssertEqual(
            cite(preprint, .vancouver),
            "Pashakhanloo F. Broken scale symmetries in undercomplete linear autoencoders. ArXiv [Preprint]. 2026 Oct 2:arXiv:2610.03640v1. PMID: 42859506."
        )
        XCTAssertTrue(cite(preprint, .apa).hasSuffix(". ArXiv. https://pubmed.ncbi.nlm.nih.gov/42859506/"), "no page slot for an arXiv id")
        XCTAssertTrue(cite(preprint, .mla).contains("ArXiv, 2026, arXiv:2610.03640v1. PubMed, "))
        XCTAssertTrue(cite(preprint, .harvard).contains("ArXiv, arXiv:2610.03640v1. Available at:"))
        XCTAssertTrue(CitationFormatter.bibtex(for: preprint).contains("note = {Preprint}"))

        var seasonal = elife
        seasonal.article?.month = "Nov-Dec"
        seasonal.article?.day = nil
        XCTAssertTrue(cite(seasonal, .vancouver).contains("Elife. 2023 Nov-Dec;12:e85096."))
        XCTAssertFalse(CitationFormatter.bibtex(for: seasonal).contains("month = "))
        XCTAssertFalse(CitationFormatter.ris(for: seasonal).contains("DA  - "))

        var lancet = elife
        lancet.article?.journalTitle = "Lancet (London, England)"
        lancet.article?.journalAbbreviation = "Lancet"
        XCTAssertTrue(cite(lancet, .apa).contains(". Lancet, 12, Article e85096."))
        XCTAssertEqual(CitationFormatter.stripJournalQualifier("BMJ (Clinical research ed.)"), "BMJ")
        XCTAssertEqual(CitationFormatter.stripJournalQualifier("(London)"), "(London)")
        XCTAssertEqual(CitationFormatter.stripJournalQualifier("Medicina (B Aires)"), "Medicina")

        XCTAssertEqual(CitationFormatter.monthNumber("Sept."), 9)
        XCTAssertEqual(CitationFormatter.monthNumber("July"), 7)
        XCTAssertEqual(CitationFormatter.monthNumber("7"), 7)
        XCTAssertNil(CitationFormatter.monthNumber("Nov-Dec"))
        XCTAssertNil(CitationFormatter.monthNumber("Spring"))
        XCTAssertNil(CitationFormatter.monthNumber("13"))
    }

    func testRetractionsDOIEncodingAndDataErrorsInAuthors() throws {
        var retracted = sciRep
        retracted.article?.publicationTypes = ["Journal Article", "Retracted Publication"]
        XCTAssertTrue(CitationFormatter.bibtex(for: retracted).contains("note = {Retracted publication}"))
        XCTAssertTrue(CitationFormatter.ris(for: retracted).contains("N1  - Retracted publication\r\n"))
        XCTAssertEqual(cite(retracted, .vancouver), cite(sciRep, .vancouver), "the citation text itself is unchanged")

        var sici = sciRep
        sici.article?.doi = "10.1002/(sici)1097-0258(19980430)17:8<857::aid-sim777>3.0.co;2-e"
        XCTAssertTrue(cite(sici, .apa).hasSuffix("https://doi.org/10.1002/(sici)1097-0258(19980430)17:8%3C857::aid-sim777%3E3.0.co;2-e"), cite(sici, .apa))
        XCTAssertTrue(cite(sici, .vancouver).contains("doi: 10.1002/(sici)1097-0258(19980430)17:8<857::aid-sim777>3.0.co;2-e."))

        let repaired = try XCTUnwrap(AuthorName(article: ArticleAuthor(lastName: "Jr", foreName: "Fedor \u{010C}iampor", initials: "F\u{010C}")))
        XCTAssertEqual(repaired.inverted(fullGivenNames: false), "\u{010C}iampor, F., Jr.")
        XCTAssertEqual(repaired.vancouver, "\u{010C}iampor F Jr")
        let genuineJr = try XCTUnwrap(AuthorName(article: ArticleAuthor(lastName: "Jr", foreName: "Ken", initials: "K")))
        XCTAssertEqual(genuineJr.surname, "Jr", "a one-token forename gives nothing to promote")

        XCTAssertNil(AuthorName.parse("[No authors listed]"))
        XCTAssertNil(AuthorName.parse("et al."))
        XCTAssertNil(AuthorName.parse("et al"))
        var anonymous = reference
        anonymous.authors = ["[No authors listed]"]
        XCTAssertTrue(cite(anonymous, .apa).hasPrefix("Type I interferon signaling precedes islet autoimmunity. (2024)."))
        var truncated = reference
        truncated.authors = ["Chen J", "et al"]
        XCTAssertTrue(cite(truncated, .vancouver).hasPrefix("Chen J. Type I"))
    }
}
