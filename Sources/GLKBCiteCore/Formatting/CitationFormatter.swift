import Foundation

/// Formats a single `LiteratureReference` in common bibliographic styles.
///
/// GLKB references carry a title, free-form authors, a journal name and a
/// year. When the reference also carries PubMed's record (`article`), the
/// citation gains what every style expects of a journal article: structured
/// author names, the journal's standard abbreviation, volume, issue, pages
/// and DOI. Without it, each style ends with the locator it gives an online
/// article: the PubMed URL (MLA, APA, Chicago, Harvard) or the PMID
/// (Vancouver).
///
/// Author strings arrive in several shapes: "C Caelles" from GLKB,
/// "Caelles C" from PubMed, "Caelles, Carme", "Carme Caelles", or a group
/// name. `AuthorName` normalises them so every style can order the surname
/// and initials its own way.
public enum CitationFormatter {
    public enum Style: String, CaseIterable, Sendable {
        case mla = "MLA"
        case apa = "APA"
        case chicago = "Chicago"
        case harvard = "Harvard"
        case vancouver = "Vancouver"

        /// The edition or variant the style follows, for labels with room
        /// for it (tooltips, accessibility descriptions).
        public var longName: String {
            switch self {
            case .mla: "MLA 9"
            case .apa: "APA 7"
            case .chicago: "Chicago 17 (notes-bibliography)"
            case .harvard: "Harvard (Cite Them Right)"
            case .vancouver: "Vancouver (NLM)"
            }
        }
    }

    /// Shown in place of a missing title so a citation is never a bare year.
    public static let untitledPlaceholder = "[Untitled]"

    /// - Parameter accessDate: the date in Harvard's "Accessed" note. It
    ///   defaults to now and is injectable for deterministic tests.
    public static func citation(
        for reference: LiteratureReference,
        style: Style,
        accessDate: Date = Date()
    ) -> String {
        formattedCitation(for: reference, style: style, accessDate: accessDate).plainText
    }

    /// The citation as styled runs. Journal titles are italic in MLA, APA,
    /// Chicago and Harvard, as are APA's volume numbers and the PubMed
    /// database name in MLA's second container; article titles stay roman in
    /// every style, and Vancouver uses no italics at all.
    public static func formattedCitation(
        for reference: LiteratureReference,
        style: Style,
        accessDate: Date = Date()
    ) -> FormattedCitation {
        let record = CitationRecord(reference)
        let runs: Runs
        switch style {
        case .mla: runs = mla(record)
        case .apa: runs = apa(record)
        case .chicago: runs = chicago(record)
        case .harvard: runs = harvard(record, accessDate: accessDate)
        case .vancouver: runs = vancouver(record)
        }
        return FormattedCitation(runs: runs)
    }

    // MARK: - Styles

    /// MLA 9: Author. "Title." Journal, vol. V, no. I, Year, pp. P, DOI.
    /// Without a DOI the database and its URL form a second container.
    private static func mla(_ record: CitationRecord) -> Runs {
        var parts: [Runs] = []
        if let head = authorBlock(record.authors, style: .mla) { parts.append(plain(head)) }
        parts.append(plain("\u{201C}\(record.titleSentence)\u{201D}"))

        var container: [Runs] = []
        if !record.journal.isEmpty { container.append(italic(record.journal)) }
        if !record.volume.isEmpty { container.append(plain("vol. \(record.volume)")) }
        if !record.issue.isEmpty { container.append(plain("no. \(record.issue)")) }
        if !record.year.isEmpty { container.append(plain(record.year)) }
        if let pages = record.pages {
            container.append(plain(pages.isRange ? "pp. \(pages.abbreviated)" : "p. \(pages.start)"))
        }
        if let doi = record.doiURL {
            container.append(plain(doi.absoluteString))
            parts.append(joined(container, separator: ", ") + plain("."))
        } else {
            if !container.isEmpty { parts.append(joined(container, separator: ", ") + plain(".")) }
            if let url = record.pubmedURL {
                parts.append(italic("PubMed") + plain(", \(url.absoluteString)."))
            } else if let url = record.fallbackURL {
                parts.append(plain("\(url.absoluteString)."))
            }
        }
        return joined(parts, separator: " ")
    }

    /// APA 7: Author, A. A., & Author, B. B. (Year). Title. Journal, V(I),
    /// pages. https://doi.org/…
    private static func apa(_ record: CitationRecord) -> Runs {
        let date = record.year.isEmpty ? "n.d." : record.year
        var parts: [Runs] = []
        if let head = authorBlock(record.authors, style: .apa) {
            parts += [plain(head), plain("(\(date))."), plain(record.titleSentence)]
        } else {
            parts += [plain(record.titleSentence), plain("(\(date)).")]
        }
        var source: [Runs] = []
        if !record.journal.isEmpty { source.append(italic(record.journal)) }
        if !record.volume.isEmpty {
            // APA italicises the volume but not the issue in parentheses.
            source.append(italic(record.volume) + (record.issue.isEmpty ? [] : plain("(\(record.issue))")))
        }
        if let pages = record.pages { source.append(plain(pages.full)) }
        if !source.isEmpty { parts.append(joined(source, separator: ", ") + plain(".")) }
        if let url = record.locatorURL { parts.append(plain(url.absoluteString)) }
        return joined(parts, separator: " ")
    }

    /// Chicago 17 bibliography: Author, A., B. Author, and C. Author.
    /// "Title." Journal V, no. I (Year): pages. https://doi.org/….
    private static func chicago(_ record: CitationRecord) -> Runs {
        var parts: [Runs] = []
        if let head = authorBlock(record.authors, style: .chicago) { parts.append(plain(head)) }
        parts.append(plain("\u{201C}\(record.titleSentence)\u{201D}"))
        if !record.volume.isEmpty {
            var source = record.journal.isEmpty ? plain(record.volume) : italic(record.journal) + plain(" \(record.volume)")
            if !record.issue.isEmpty { source += plain(", no. \(record.issue)") }
            if !record.year.isEmpty { source += plain(" (\(record.year))") }
            if let pages = record.pages { source += plain(": \(pages.abbreviated)") }
            parts.append(source + plain("."))
        } else if let source = container(record.journal, record.year, separator: ", ", undated: "n.d.", italicJournal: true) {
            parts.append(source)
        }
        if let url = record.locatorURL { parts.append(plain("\(url.absoluteString).")) }
        return joined(parts, separator: " ")
    }

    /// Harvard (Cite Them Right): Author, A., Author, B. and Author, C.
    /// (Year) 'Title', Journal, V(I), pp. pages. Available at: URL
    /// (Accessed: Day Month Year).
    private static func harvard(_ record: CitationRecord, accessDate: Date) -> Runs {
        let date = record.year.isEmpty ? "no date" : record.year
        let quotedTitle = "\u{2018}\(record.title)\u{2019}"
        var source: [Runs] = []
        if !record.journal.isEmpty { source.append(italic(record.journal)) }
        if !record.volume.isEmpty { source.append(plain(record.volumeWithIssue)) }
        if let pages = record.pages {
            source.append(plain(pages.isRange ? "pp. \(pages.full)" : "p. \(pages.start)"))
        }
        var runs: Runs
        if let authorsText = authorBlock(record.authors, style: .harvard) {
            runs = plain("\(authorsText) (\(date)) \(quotedTitle)")
            runs += source.isEmpty ? plain(record.titleStop) : plain(", ") + joined(source, separator: ", ") + plain(".")
        } else {
            runs = plain("\(quotedTitle) (\(date))")
            runs += source.isEmpty ? plain(".") : plain(" ") + joined(source, separator: ", ") + plain(".")
        }
        if let url = record.locatorURL {
            runs += plain(" Available at: \(url.absoluteString) (Accessed: \(harvardDate(accessDate))).")
        }
        return runs
    }

    /// Vancouver / NLM: Author AA, Author BB. Title. J Abbrev. Year Mon
    /// Day;V(I):pages. doi: …. PMID: n.
    private static func vancouver(_ record: CitationRecord) -> Runs {
        var parts: [String] = []
        if let head = authorBlock(record.authors, style: .vancouver) { parts.append(head) }
        parts.append(record.titleSentence)
        let journal = record.journalAbbreviation.isEmpty ? record.journal : record.journalAbbreviation
        if !journal.isEmpty { parts.append("\(journal).") }

        let date = [record.year, record.monthName, record.day].filter { !$0.isEmpty }.joined(separator: " ")
        var source = date
        if !record.volume.isEmpty {
            source += (source.isEmpty ? "" : ";") + record.volumeWithIssue
        }
        if let pages = record.pages {
            source += source.isEmpty ? pages.medline : ":\(pages.medline)"
        }
        if !source.isEmpty { parts.append("\(source).") }
        if !record.doi.isEmpty { parts.append("doi: \(record.doi).") }
        if !record.pmid.isEmpty { parts.append("PMID: \(record.pmid).") }
        return plain(parts.joined(separator: " "))
    }

    // MARK: - Exports

    /// BibTeX `@article` entry.
    public static func bibtex(for reference: LiteratureReference) -> String {
        let record = CitationRecord(reference)
        // Field values are escaped here, piece by piece, so the braces that
        // protect a group author's name survive. `raw` values (BibTeX month
        // macros) are emitted without braces.
        var fields: [(name: String, value: String, raw: Bool)] = []
        if !record.authors.isEmpty {
            fields.append(("author", record.authors.map { $0.bibtex(escaping: escapeBibTeX) }.joined(separator: " and "), false))
        }
        // The inner braces keep the title's capitalisation as written; most
        // BibTeX styles lower-case an unprotected title.
        fields.append(("title", "{\(escapeBibTeX(record.title))}", false))
        if !record.journal.isEmpty { fields.append(("journal", escapeBibTeX(record.journal), false)) }
        if !record.year.isEmpty { fields.append(("year", record.year, false)) }
        if let macro = record.monthMacro { fields.append(("month", macro, true)) }
        if !record.volume.isEmpty { fields.append(("volume", escapeBibTeX(record.volume), false)) }
        if !record.issue.isEmpty { fields.append(("number", escapeBibTeX(record.issue), false)) }
        if let pages = record.pages {
            fields.append(("pages", escapeBibTeX(pages.end.map { "\(pages.start)--\($0)" } ?? pages.start), false))
        }
        if !record.doi.isEmpty { fields.append(("doi", record.doi.filter { $0 != "{" && $0 != "}" }, false)) }
        if !record.pmid.isEmpty { fields.append(("pmid", record.pmid, false)) }
        if let url = record.pubmedURL ?? record.fallbackURL {
            // URLs are not TeX-escaped: the url/hyperref packages read the
            // field verbatim, and an escaped "%" would break the link.
            fields.append(("url", url.absoluteString.filter { $0 != "{" && $0 != "}" && !$0.isWhitespace }, false))
        }
        let body = fields
            .map { $0.raw ? "  \($0.name) = \($0.value)" : "  \($0.name) = {\($0.value)}" }
            .joined(separator: ",\n")
        return "@article{\(bibtexKey(for: reference)),\n\(body)\n}"
    }

    /// EndNote-compatible RIS record: CRLF line ends and a terminating
    /// newline, as the RIS specification and EndNote's importer expect.
    public static func ris(for reference: LiteratureReference) -> String {
        let record = CitationRecord(reference)
        var lines = ["TY  - JOUR"]
        for author in record.authors {
            lines.append("AU  - \(author.ris)")
        }
        lines.append("TI  - \(record.title)")
        if !record.journal.isEmpty {
            // T2 is the periodical title for a journal article; JO carries
            // the standard abbreviation (EndNote's "Alternate Journal").
            lines.append("T2  - \(record.journal)")
        }
        if !record.journalAbbreviation.isEmpty, record.journalAbbreviation != record.journal {
            lines.append("JO  - \(record.journalAbbreviation)")
        }
        if !record.volume.isEmpty { lines.append("VL  - \(record.volume)") }
        if !record.issue.isEmpty { lines.append("IS  - \(record.issue)") }
        if let pages = record.pages {
            lines.append("SP  - \(pages.start)")
            if let end = pages.end { lines.append("EP  - \(end)") }
        }
        if !record.year.isEmpty {
            lines.append("PY  - \(record.year)")
            if let month = record.monthNumber {
                let day = Int(record.day).map { String(format: "%02d", $0) } ?? ""
                lines.append("DA  - \(record.year)/\(String(format: "%02d", month))/\(day)/")
            }
        }
        if !record.doi.isEmpty { lines.append("DO  - \(record.doi)") }
        if !record.pmid.isEmpty {
            lines.append("AN  - \(record.pmid)")
            lines.append("DB  - PubMed")
        }
        if let url = record.pubmedURL ?? record.fallbackURL {
            lines.append("UR  - \(url.absoluteString)")
        }
        lines.append("ER  - ")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Author lists

    /// The author element of a citation, or nil when there are no authors.
    /// Every style but Harvard ends with a full stop; Harvard's year follows
    /// the names directly.
    private static func authorBlock(_ names: [AuthorName], style: Style) -> String? {
        guard !names.isEmpty else { return nil }
        let text: String
        switch style {
        case .mla:
            // MLA 9: one author inverted; two with "and"; three or more → et al.
            let first = names[0].inverted(fullGivenNames: true)
            switch names.count {
            case 1: text = first
            case 2: text = "\(first), and \(names[1].natural(fullGivenNames: true))"
            default: text = "\(first), et al"
            }

        case .apa:
            // APA 7: all authors inverted, "&" before the last, up to 20;
            // beyond that the first 19, an ellipsis, and the final author.
            let inverted = names.map { $0.inverted(fullGivenNames: false) }
            if inverted.count == 1 {
                text = inverted[0]
            } else if inverted.count <= 20 {
                text = inverted.dropLast().joined(separator: ", ") + ", & " + inverted[inverted.count - 1]
            } else {
                text = inverted.prefix(19).joined(separator: ", ") + ", . . . " + inverted[inverted.count - 1]
            }

        case .chicago:
            // Chicago 17 bibliography: first author inverted, the rest in
            // natural order, "and" before the last, up to ten; more than ten
            // → the first seven and et al.
            let first = names[0].inverted(fullGivenNames: true)
            let rest = names.dropFirst().map { $0.natural(fullGivenNames: true) }
            if rest.isEmpty {
                text = first
            } else if names.count <= 10 {
                text = ([first] + rest.dropLast()).joined(separator: ", ") + ", and " + rest[rest.count - 1]
            } else {
                text = ([first] + rest.prefix(6)).joined(separator: ", ") + ", et al"
            }

        case .harvard:
            // Harvard (Cite Them Right): up to three authors inverted with
            // "and" before the last; four or more → first author et al.
            let inverted = names.map { $0.inverted(fullGivenNames: false) }
            switch inverted.count {
            case 1: return inverted[0]
            case 2: return "\(inverted[0]) and \(inverted[1])"
            case 3: return "\(inverted[0]), \(inverted[1]) and \(inverted[2])"
            default: return "\(inverted[0]) et al."
            }

        case .vancouver:
            // Vancouver/NLM: surname and run-together initials, the first
            // six authors, then et al.
            let shown = names.prefix(6).map(\.vancouver).joined(separator: ", ")
            text = names.count > 6 ? "\(shown), et al" : shown
        }
        return text.hasSuffix(".") ? text : "\(text)."
    }

    /// Journal and year as one element, in the style's punctuation, or nil
    /// when both are missing. `undated` is the placeholder a style uses for
    /// a journal without a year ("n.d."), nil to omit the year; the journal
    /// is italic where the style sets it so.
    private static func container(
        _ journal: String, _ year: String, separator: String, undated: String?, italicJournal: Bool
    ) -> Runs? {
        let journalRuns = italicJournal ? italic(journal) : plain(journal)
        switch (journal.isEmpty, year.isEmpty) {
        case (false, false): return journalRuns + plain("\(separator)\(year).")
        case (false, true):
            guard let undated else { return journalRuns + plain(".") }
            return journalRuns + plain("\(separator)\(undated)\(undated.hasSuffix(".") ? "" : ".")")
        case (true, false): return plain("\(year).")
        case (true, true): return nil
        }
    }

    // MARK: - Styled runs

    private typealias Runs = [FormattedCitation.Run]

    private static func plain(_ text: String) -> Runs { [FormattedCitation.Run(text: text, isItalic: false)] }
    private static func italic(_ text: String) -> Runs { [FormattedCitation.Run(text: text, isItalic: true)] }

    /// Joins the parts of a citation with `separator`.
    private static func joined(_ parts: [Runs], separator: String) -> Runs {
        var result: Runs = []
        for (index, part) in parts.enumerated() {
            if index > 0 { result += plain(separator) }
            result += part
        }
        return result
    }

    // MARK: - Pieces

    /// Years a publication date can plausibly carry. Anything else in the
    /// date text (page-like numbers, "0000", non-ASCII digits) is ignored.
    static let plausibleYears = 1500 ... 2100

    /// Extracts a 4-digit year from free-form date text such as `"2024"`,
    /// `"2024 Mar"`, `"2024-03-12"` or `"20240312"`. Only ASCII digits
    /// count; `Character.isNumber` would also accept superscripts, Arabic-
    /// Indic digits and fractions.
    static func year(from date: String?) -> String {
        guard let date else { return "" }
        func year(in run: String) -> String? {
            let digits = run.count == 8 ? String(run.prefix(4)) : run
            guard digits.count == 4, let value = Int(digits), plausibleYears.contains(value) else { return nil }
            return digits
        }
        var run = ""
        for scalar in date.unicodeScalars {
            if scalar.isASCII, ("0" ... "9").contains(scalar) {
                run.unicodeScalars.append(scalar)
            } else {
                if let found = year(in: run) { return found }
                run = ""
            }
        }
        return year(in: run) ?? ""
    }

    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// 1…12 from "Jul", "July", "07" or "7"; nil for seasons and ranges.
    static func monthNumber(_ text: String) -> Int? {
        let cleaned = clean(text)
        if let number = Int(cleaned), (1 ... 12).contains(number) { return number }
        let key = cleaned.prefix(3).lowercased()
        guard key.count == 3, let index = monthNames.firstIndex(where: { $0.lowercased() == key }) else { return nil }
        return index + 1
    }

    private static func harvardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    static func clean(_ value: String) -> String {
        LiteratureNetworking.clean(value)
    }

    /// Titles from PubMed frequently end with a period already; strip it so
    /// style templates control the final punctuation.
    private static func cleanTitle(_ value: String) -> String {
        var title = clean(value)
        while title.hasSuffix(".") { title.removeLast() }
        return clean(title)
    }

    static func displayTitle(_ value: String) -> String {
        let title = cleanTitle(value)
        return title.isEmpty ? untitledPlaceholder : title
    }

    /// A title ending in "?" or "!" keeps that mark instead of gaining a
    /// second stop.
    static func endsWithTerminalPunctuation(_ title: String) -> Bool {
        title.hasSuffix("?") || title.hasSuffix("!")
    }

    /// Only web URLs are cited; a reference built by hand could carry any
    /// scheme.
    static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    /// A bare DOI ("10.1038/370220a0") from the forms PubMed and users
    /// write: "doi: …", "https://doi.org/…", "http://dx.doi.org/…".
    static func normalizedDOI(_ value: String?) -> String {
        guard let value else { return "" }
        var doi = clean(value)
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:", "DOI:"] {
            if doi.lowercased().hasPrefix(prefix.lowercased()) {
                doi = clean(String(doi.dropFirst(prefix.count)))
                break
            }
        }
        return doi.hasPrefix("10.") ? doi : ""
    }

    private static let journalSmallWords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to",
        "de", "del", "der", "des", "di", "du", "e", "et", "für", "la", "le", "und", "van", "von", "y", "zu",
    ]

    /// PubMed catalogues journals in sentence case ("Scientific reports",
    /// "The Journal of clinical investigation"); citation styles print the
    /// title in headline case. Words that already carry capitals ("mAbs",
    /// "BMJ") are left alone.
    static func journalCase(_ name: String) -> String {
        var output: [String] = []
        var sentenceStart = true
        for word in clean(name).split(separator: " ").map(String.init) {
            let lowered = word.lowercased()
            let isAllLowercase = word == lowered
            let core = lowered.trimmingCharacters(in: .punctuationCharacters)
            if isAllLowercase, sentenceStart || !journalSmallWords.contains(core),
               let letter = word.firstIndex(where: \.isLetter) {
                var capitalised = word
                capitalised.replaceSubrange(letter ... letter, with: word[letter].uppercased())
                output.append(capitalised)
            } else {
                output.append(word)
            }
            sentenceStart = word.hasSuffix(".") || word.hasSuffix(":")
        }
        return output.joined(separator: " ")
    }

    /// A key BibTeX accepts: `pmid` plus the number, or `glkb` with whatever
    /// ASCII letters and digits a non-PubMed identifier contains.
    private static func bibtexKey(for reference: LiteratureReference) -> String {
        if let pmid = PubMed.canonicalPMID(reference.pmid) { return "pmid\(pmid)" }
        let safe = reference.pmid.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return safe.isEmpty ? "glkb" : "glkb-\(safe)"
    }

    /// Escapes every TeX special character in one pass, so no replacement
    /// can re-match the output of an earlier one.
    static func escapeBibTeX(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": output += "\\textbackslash{}"
            case "{": output += "\\{"
            case "}": output += "\\}"
            case "%", "&", "_", "#", "$": output += "\\\(character)"
            case "~": output += "\\textasciitilde{}"
            case "^": output += "\\textasciicircum{}"
            default: output.append(character)
            }
        }
        return output
    }
}

// MARK: - Record

/// Everything a style needs, merged from GLKB's reference and PubMed's
/// record (which wins wherever it has a value). Empty strings mean unknown.
struct CitationRecord {
    let authors: [AuthorName]
    let title: String
    let journal: String
    let journalAbbreviation: String
    let year: String
    let month: String
    let day: String
    let volume: String
    let issue: String
    let pages: PageRange?
    let doi: String
    let pmid: String
    let pubmedURL: URL?
    let fallbackURL: URL?

    init(_ reference: LiteratureReference) {
        let article = reference.article
        let articleAuthors = article?.authors.compactMap(AuthorName.init(article:)) ?? []
        authors = articleAuthors.isEmpty ? reference.authors.compactMap(AuthorName.parse) : articleAuthors
        title = CitationFormatter.displayTitle(article?.title ?? reference.title)
        journal = CitationFormatter.journalCase(article?.journalTitle ?? reference.journal ?? "")
        journalAbbreviation = CitationFormatter.clean(article?.journalAbbreviation ?? "")
        let articleYear = CitationFormatter.year(from: article?.year)
        year = articleYear.isEmpty ? CitationFormatter.year(from: reference.date) : articleYear
        month = CitationFormatter.clean(article?.month ?? "")
        day = CitationFormatter.clean(article?.day ?? "")
        volume = CitationFormatter.clean(article?.volume ?? "")
        issue = CitationFormatter.clean(article?.issue ?? "")
        pages = article?.pages.flatMap(PageRange.init(medline:))
        doi = CitationFormatter.normalizedDOI(article?.doi)
        pmid = PubMed.canonicalPMID(reference.pmid) ?? ""
        pubmedURL = PubMed.url(for: reference.pmid)
        fallbackURL = CitationFormatter.webURL(reference.url)
    }

    var titleSentence: String {
        CitationFormatter.endsWithTerminalPunctuation(title) ? title : "\(title)."
    }

    var titleStop: String {
        CitationFormatter.endsWithTerminalPunctuation(title) ? "" : "."
    }

    /// "370(6486)" or "370".
    var volumeWithIssue: String {
        issue.isEmpty ? volume : "\(volume)(\(issue))"
    }

    var doiURL: URL? {
        doi.isEmpty ? nil : URL(string: "https://doi.org/\(doi)")
    }

    /// The best locator: DOI, else PubMed, else the reference's own web URL.
    var locatorURL: URL? {
        doiURL ?? pubmedURL ?? fallbackURL
    }

    var monthNumber: Int? {
        CitationFormatter.monthNumber(month)
    }

    /// "Jul" for both "Jul" and "07"; seasons and ranges as given.
    var monthName: String {
        monthNumber.map { CitationFormatter.monthNames[$0 - 1] } ?? month
    }

    /// BibTeX's month macro ("jul"), nil for seasons and ranges.
    var monthMacro: String? {
        monthNumber.map { CitationFormatter.monthNames[$0 - 1].lowercased() }
    }
}

/// A MEDLINE page string, split and expanded: "220-3" is 220–223.
struct PageRange: Equatable {
    let start: String
    /// The expanded end page, nil for a single page or article number.
    let end: String?
    /// As PubMed gives it, which is also how Vancouver prints it.
    let medline: String

    init?(medline raw: String) {
        // "220-3; discussion 230-5" cites only the article itself.
        let text = CitationFormatter.clean(String(raw.split(separator: ";").first ?? ""))
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: "-", maxSplits: 1).map { CitationFormatter.clean(String($0)) }
        guard let first = parts.first, !first.isEmpty else { return nil }
        start = first
        var last = parts.count > 1 ? parts[1] : ""
        if !last.isEmpty, first.allSatisfy(\.isNumber), last.allSatisfy(\.isNumber), last.count < first.count {
            last = String(first.prefix(first.count - last.count)) + last
        }
        end = last.isEmpty ? nil : last
        medline = text
    }

    var isRange: Bool { end != nil }

    /// "220–223".
    var full: String {
        end.map { "\(start)\u{2013}\($0)" } ?? start
    }

    /// Chicago/MLA abbreviation (CMOS 9.61): "220–23", "101–8", "498–532",
    /// "1087–89"; ranges under 100 or starting on a hundred are left whole.
    var abbreviated: String {
        guard let end else { return start }
        guard let first = Int(start), let last = Int(end), last > first, start.count == end.count else { return full }
        if first < 100 || first % 100 == 0 { return full }
        let shared = zip(start, end).prefix(while: { $0 == $1 }).count
        var suffix = String(end.dropFirst(shared))
        if (1 ... 9).contains(first % 100) {
            if suffix.isEmpty { suffix = String(end.suffix(1)) }
        } else if suffix.count < 2 {
            suffix = String(end.suffix(2))
        }
        return "\(start)\u{2013}\(suffix)"
    }
}

// MARK: - Author names

/// One author, parsed from the free-form strings the API returns.
struct AuthorName: Equatable {
    /// Family name, including particles ("van der Berg").
    var surname: String
    /// Given names or initials as written: ["Carme"], ["C"], ["CA"], ["Jean-Pierre"].
    var givenNames: [String]
    /// Generational suffix such as "Jr" or "III".
    var suffix: String?
    /// A group author ("WHO Study Group"), printed verbatim in every style.
    var isCorporate: Bool
    /// Initials as PubMed records them ("TH" for "Thi Hong Ha"); derived
    /// from the given names when absent.
    var initials: String? = nil

    /// Accepts "Caelles C", "Caelles CA", "C Caelles", "C A Caelles",
    /// "Caelles, Carme", "Carme Caelles", "J van der Berg", "Smith J Jr",
    /// "Smith III", "Smith, Jr." and group names. Returns nil for an empty
    /// string.
    ///
    /// Two shapes stay ambiguous and follow the PubMed/GLKB convention:
    /// "M Garcia Lopez" is a compound surname (not a given name "Garcia"),
    /// and "Ivanov IV" has the initials I. V. (not a suffix).
    static func parse(_ raw: String) -> AuthorName? {
        let text = LiteratureNetworking.clean(raw)
        guard !text.isEmpty else { return nil }
        if looksCorporate(text) {
            return AuthorName(surname: text, givenNames: [], suffix: nil, isCorporate: true)
        }

        if let comma = text.firstIndex(of: ",") {
            // "Surname, Given Names[, Suffix]" — the surname is already
            // separated, so the suffix may be the only thing after the comma.
            let surname = text[..<comma].trimmingCharacters(in: .whitespaces)
            var given = text[text.index(after: comma)...]
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map(String.init)
            let suffix = takeSuffix(&given, minimumRemaining: 0)
            guard !surname.isEmpty else { return nil }
            return AuthorName(surname: surname, givenNames: given, suffix: suffix, isCorporate: false)
        }

        var tokens = text.split(separator: " ").map(String.init)
        let suffix = takeSuffix(&tokens, minimumRemaining: 1)
        guard let first = tokens.first else { return nil }
        if tokens.count == 1 {
            return AuthorName(surname: first, givenNames: [], suffix: suffix, isCorporate: false)
        }
        let last = tokens[tokens.count - 1]
        switch (isInitialsToken(first), isInitialsToken(last)) {
        case (false, true):
            // PubMed order: "Caelles C", "van der Berg JA"
            return AuthorName(
                surname: tokens.dropLast().joined(separator: " "),
                givenNames: [last], suffix: suffix, isCorporate: false
            )
        case (true, false):
            // GLKB order: "C Caelles", "C A Caelles", "J van der Berg"
            let given = tokens.prefix(while: isInitialsToken)
            return AuthorName(
                surname: tokens.dropFirst(given.count).joined(separator: " "),
                givenNames: Array(given), suffix: suffix, isCorporate: false
            )
        case (true, true):
            // Both look like initials ("LI Y" / "Y LI"): the longer token is
            // the surname; ties follow PubMed order.
            if last.count > first.count {
                return AuthorName(
                    surname: last, givenNames: Array(tokens.dropLast()), suffix: suffix, isCorporate: false
                )
            }
            return AuthorName(
                surname: first, givenNames: Array(tokens.dropFirst()), suffix: suffix, isCorporate: false
            )
        case (false, false):
            // Full given names first: "Carme Caelles", "Jean Pierre de la Fontaine"
            var surnameStart = tokens.count - 1
            while surnameStart > 1, isParticle(tokens[surnameStart - 1]) { surnameStart -= 1 }
            return AuthorName(
                surname: tokens[surnameStart...].joined(separator: " "),
                givenNames: Array(tokens[..<surnameStart]), suffix: suffix, isCorporate: false
            )
        }
    }

    // MARK: Renderings

    /// "Caelles, C. A." / "Caelles, Carme" / "Smith, J., Jr."
    func inverted(fullGivenNames: Bool) -> String {
        if isCorporate { return surname }
        var text = surname
        let given = givenText(full: fullGivenNames)
        if !given.isEmpty { text += ", \(given)" }
        if let suffix = proseSuffix { text += ", \(suffix)" }
        return text
    }

    /// "C. A. Caelles" / "Carme Caelles" / "J. Smith Jr."
    func natural(fullGivenNames: Bool) -> String {
        if isCorporate { return surname }
        return [givenText(full: fullGivenNames), surname, proseSuffix ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// NLM form: "Caelles CA", "Smith J Jr".
    var vancouver: String {
        if isCorporate { return surname }
        return [surname, compactInitials, suffix ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// BibTeX "von Last, Jr, First" form; group names are brace-protected.
    /// `escape` is applied to each piece before the braces are added.
    func bibtex(escaping escape: (String) -> String) -> String {
        if isCorporate { return "{\(escape(surname))}" }
        var text = escape(surname)
        if let suffix = proseSuffix { text += ", \(escape(suffix))" }
        let given = givenText(full: true)
        if !given.isEmpty { text += ", \(escape(given))" }
        return text
    }

    /// RIS "Lastname, Firstname, Suffix" form.
    var ris: String { inverted(fullGivenNames: true) }

    // MARK: Pieces

    /// "Jr." and "Sr." take a period in prose styles; numerals do not.
    private var proseSuffix: String? {
        guard let suffix else { return nil }
        return ["jr", "sr"].contains(suffix.lowercased()) ? "\(suffix)." : suffix
    }

    /// Given names as written when any is a full name, initials otherwise.
    private func givenText(full: Bool) -> String {
        guard !givenNames.isEmpty else { return "" }
        guard full else { return spacedInitials }
        return givenNames
            .map { Self.isInitialsToken($0) ? Self.spaced(Self.initialLetters(of: $0)) : $0 }
            .joined(separator: " ")
    }

    /// "C. A." / "J.-P."
    private var spacedInitials: String {
        if let initials {
            return initials.filter(\.isLetter).map { "\($0)." }.joined(separator: " ")
        }
        return givenNames.map { Self.spaced(Self.initialLetters(of: $0)) }.joined(separator: " ")
    }

    /// "CA" / "JP"
    private var compactInitials: String {
        if let initials { return initials.filter(\.isLetter) }
        return givenNames.flatMap { Self.initialLetters(of: $0).flatMap { $0 } }.joined()
    }

    /// Initial letters per hyphenated part: "Jean-Pierre" → [["J"], ["P"]],
    /// "CA" → [["C", "A"]], "C." → [["C"]].
    private static func initialLetters(of token: String) -> [[String]] {
        token.split(separator: "-").map { part -> [String] in
            let core = part.filter { $0 != "." }
            if isInitialsToken(String(core)) {
                return core.map { String($0) }
            }
            return core.first.map { [String($0).uppercased()] } ?? []
        }
    }

    private static func spaced(_ letters: [[String]]) -> String {
        letters
            .map { $0.map { "\($0)." }.joined(separator: " ") }
            .joined(separator: "-")
    }

    /// "C", "CA", "C.A.", "J-P": up to three capital letters.
    private static func isInitialsToken(_ token: String) -> Bool {
        let core = token.filter { $0 != "." && $0 != "-" }
        return !core.isEmpty && core.count <= 3 && core.allSatisfy(\.isUppercase)
    }

    private static let particles: Set<String> = [
        "van", "von", "vander", "vanden", "de", "der", "den", "del", "della", "delle", "di", "da",
        "do", "dos", "das", "du", "la", "le", "les", "ter", "ten", "af", "av", "zu", "zur",
        "bin", "ibn", "al", "el", "y", "e", "of",
    ]

    /// "van", and capitalised forms of two or more letters ("Van", "De"):
    /// single letters stay initials ("J Y Lee").
    private static func isParticle(_ token: String) -> Bool {
        let lower = token.lowercased()
        guard particles.contains(lower) else { return false }
        if token == lower { return true }
        return token.count >= 2 && token == lower.prefix(1).uppercased() + lower.dropFirst()
    }

    private static let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "2nd", "3rd"]

    private static func isSuffixToken(_ token: String) -> Bool {
        suffixes.contains(token.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).lowercased())
    }

    /// Removes a trailing generational suffix and returns it. At least
    /// `minimumRemaining` tokens must stay (the surname in a plain name;
    /// nothing after a comma, where the surname is already separated).
    private static func takeSuffix(_ tokens: inout [String], minimumRemaining: Int) -> String? {
        guard tokens.count > minimumRemaining, let last = tokens.last else { return nil }
        let bare = last.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        let key = bare.lowercased()
        guard suffixes.contains(key) else { return nil }
        // "II"/"IV" are also plausible initials ("Ivanov IV"); only treat
        // them as a suffix once a given name is present as well.
        if ["ii", "iv"].contains(key), tokens.count < minimumRemaining + 2 { return nil }
        tokens.removeLast()
        return bare
    }

    private static let corporateMarkers = [
        "group", "consortium", "collaboration", "collaborative", "collaborators", "investigators",
        "committee", "network", "team", "study", "society", "association", "institute",
        "organization", "organisation", "project", "alliance", "foundation", "center", "centre",
        "centers", "centres", "initiative", "trial", "panel", "program", "programme", "working",
        "council", "agency", "department", "university", "hospital", "laboratory", "cohort",
        "registry", "task force",
    ]

    /// Group authors contain digits or an organisational word. A trailing
    /// generational suffix ("2nd") is not a digit of a group name, and a
    /// marker word next to an initial ("Study A", "A Study") is a person's
    /// surname, as is a marker word on its own.
    private static func looksCorporate(_ text: String) -> Bool {
        var words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        while words.count > 1, let last = words.last, isSuffixToken(last) { words.removeLast() }
        if words.contains(where: { $0.contains(where: \.isNumber) }) { return true }

        let lowered = words.map { word in String(word.lowercased().filter { $0.isLetter || $0 == "-" }) }
        let joined = lowered.joined(separator: " ")
        for marker in corporateMarkers where marker.contains(" ") {
            if joined.contains(marker) { return true }
        }
        guard lowered.contains(where: corporateMarkers.contains) else { return false }
        switch lowered.count {
        case 1: return false
        case 2: return !words.contains(where: isInitialsToken)
        default: return true
        }
    }
}

// A struct with an initializer in its body loses the memberwise one `parse`
// relies on; the PubMed initializer therefore lives in an extension.
extension AuthorName {
    /// From PubMed's structured name parts. Returns nil for an author
    /// record with neither a surname nor a group name.
    init?(article author: ArticleAuthor) {
        if let collective = author.collectiveName.map(LiteratureNetworking.clean), !collective.isEmpty {
            self.init(surname: collective, givenNames: [], suffix: nil, isCorporate: true)
            return
        }
        guard let surname = author.lastName.map(LiteratureNetworking.clean), !surname.isEmpty else { return nil }
        var given = LiteratureNetworking.clean(author.foreName ?? "").split(separator: " ").map(String.init)
        let initials = author.initials.map(LiteratureNetworking.clean).flatMap { $0.isEmpty ? nil : $0 }
        if given.isEmpty, let initials { given = [initials] }
        self.init(
            surname: surname,
            givenNames: given,
            suffix: author.suffix.map(LiteratureNetworking.clean).flatMap { $0.isEmpty ? nil : $0 },
            isCorporate: false,
            initials: initials
        )
    }
}
