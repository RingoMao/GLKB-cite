import Foundation

/// Formats a single `LiteratureReference` in common bibliographic styles.
///
/// GLKB references carry PubMed metadata: authors, title, journal, year and
/// PMID, plus volume, issue, pages and DOI when the API supplies them. A
/// reference with a DOI ends with its https://doi.org link; one without
/// ends with the locator a style gives an online article lacking it: the
/// PubMed URL (MLA, APA, Chicago, Harvard) or the PMID (Vancouver).
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
    }

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
    /// Chicago and Harvard, as are APA volume numbers and the PubMed database
    /// name in MLA's second container; article titles stay roman in every
    /// style, and Vancouver uses no italics at all.
    public static func formattedCitation(
        for reference: LiteratureReference,
        style: Style,
        accessDate: Date = Date()
    ) -> FormattedCitation {
        let authors = reference.authors.compactMap(AuthorName.parse)
        let title = cleanTitle(reference.title)
        let titleSentence = endsWithTerminalPunctuation(title) ? title : "\(title)."
        let journal = journalTitle(clean(reference.journal ?? ""))
        let year = year(from: reference.date)
        let pmid = clean(reference.pmid)
        let volume = nonEmpty(reference.volume)
        let issue = nonEmpty(reference.issue)
        let rawPages = nonEmpty(reference.pages)
        let pages = rawPages.map(pageRange)
        let doi = nonEmpty(reference.doi)
        // A DOI is the preferred locator in every style that prints a link.
        let doiLink = doi.flatMap(doiURL)
        let link = doiLink ?? PubMed.url(for: reference.pmid) ?? reference.url
        let url = doiLink.map { _ in "https://doi.org/\(doi ?? "")" } ?? link?.absoluteString ?? ""
        var parts: [Runs] = []

        switch style {
        case .mla:
            // Author. "Title." Journal, vol. V, no. I, Year, pp. P. DOI.
            // Without a DOI: … Database, URL.
            if let head = authorBlock(authors, style: style) { parts.append(plain(head)) }
            parts.append(plain("\u{201C}\(titleSentence)\u{201D}"))
            var elements: [Runs] = []
            if !journal.isEmpty { elements.append(italic(journal)) }
            if let volume { elements.append(plain("vol. \(volume)")) }
            if let issue { elements.append(plain("no. \(issue)")) }
            if !year.isEmpty { elements.append(plain(year)) }
            if let pages { elements.append(plain("\(pagePrefix(pages)) \(pages)")) }
            if !elements.isEmpty { parts.append(joined(elements, separator: ", ") + plain(".")) }
            if doiLink != nil {
                parts.append(linked(url, link) + plain("."))
            } else if !url.isEmpty {
                parts.append(italic("PubMed") + plain(", ") + linked(url, link) + plain("."))
            }

        case .apa:
            // Author, A. A., & Author, B. B. (Year). Title. Journal, Volume(Issue), Pages. DOI or URL
            let date = year.isEmpty ? "n.d." : year
            if let head = authorBlock(authors, style: style) {
                parts += [plain(head), plain("(\(date))."), plain(titleSentence)]
            } else {
                parts += [plain(titleSentence), plain("(\(date)).")]
            }
            if !journal.isEmpty {
                var source = italic(journal)
                if let volume {
                    source += plain(", ") + italic(volume)
                    if let issue { source += plain("(\(issue))") }
                }
                if let pages { source += plain(", \(pages)") }
                parts.append(source + plain("."))
            }
            if !url.isEmpty { parts.append(linked(url, link)) }

        case .chicago:
            // Author, A., B. Author, and C. Author. "Title." Journal Volume, no. Issue (Year): Pages. DOI or URL.
            // Without volume or pages: … Journal, Year.
            if let head = authorBlock(authors, style: style) { parts.append(plain(head)) }
            parts.append(plain("\u{201C}\(titleSentence)\u{201D}"))
            if volume == nil, pages == nil {
                if let container = container(journal, year, separator: ", ", undated: "n.d.", italicJournal: true) {
                    parts.append(container)
                }
            } else {
                var source = journal.isEmpty ? [] : italic(journal)
                if let volume { source += plain(source.isEmpty ? volume : " \(volume)") }
                if let issue { source += plain(", no. \(issue)") }
                source += plain("\(source.isEmpty ? "" : " ")(\(year.isEmpty ? "n.d." : year))")
                if let pages { source += plain(": \(pages)") }
                parts.append(source + plain("."))
            }
            if !url.isEmpty { parts.append(linked(url, link) + plain(".")) }

        case .harvard:
            // Author, A., Author, B. and Author, C. (Year) 'Title', Journal, Volume(Issue), pp. Pages.
            // Available at: DOI, or URL (Accessed: Day Month Year).
            let date = year.isEmpty ? "no date" : year
            let quotedTitle = "\u{2018}\(title)\u{2019}"
            let titleStop = endsWithTerminalPunctuation(title) ? "" : "."
            var source: Runs = []
            if !journal.isEmpty {
                source = italic(journal)
                if let volume {
                    source += plain(", \(volume)")
                    if let issue { source += plain("(\(issue))") }
                }
                if let pages { source += plain(", \(pagePrefix(pages)) \(pages)") }
                source += plain(".")
            }
            var runs: Runs
            if let authorsText = authorBlock(authors, style: style) {
                runs = plain("\(authorsText) (\(date)) \(quotedTitle)")
                runs += source.isEmpty ? plain(titleStop) : plain(", ") + source
            } else {
                runs = plain("\(quotedTitle) (\(date))")
                runs += source.isEmpty ? plain(".") : plain(" ") + source
            }
            if doiLink != nil {
                // A DOI is persistent, so Cite Them Right omits the access date.
                runs += plain(" Available at: ") + linked(url, link) + plain(".")
            } else if !url.isEmpty {
                runs += plain(" Available at: ") + linked(url, link)
                runs += plain(" (Accessed: \(harvardDate(accessDate))).")
            }
            return FormattedCitation(runs: runs)

        case .vancouver:
            // Author AA, Author BB. Title. Journal. Year;Volume(Issue):Pages. doi: D. PMID: n.
            // NLM keeps page ranges as written, with hyphens.
            if let head = authorBlock(authors, style: style) { parts.append(plain(head)) }
            parts.append(plain(titleSentence))
            if volume == nil, rawPages == nil {
                if let container = container(journal, year, separator: ". ", undated: nil, italicJournal: false) {
                    parts.append(container)
                }
            } else {
                var locator = year
                if let volume { locator += (locator.isEmpty ? "" : ";") + volume + (issue.map { "(\($0))" } ?? "") }
                if let rawPages { locator += ":\(rawPages)" }
                parts.append(plain(journal.isEmpty ? "\(locator)." : "\(journal). \(locator)."))
            }
            if let doi { parts.append(plain("doi: \(doi).")) }
            if !pmid.isEmpty { parts.append(plain("PMID: \(pmid).")) }
        }
        return FormattedCitation(runs: joined(parts))
    }

    /// BibTeX `@article` entry.
    public static func bibtex(for reference: LiteratureReference) -> String {
        let pmid = clean(reference.pmid)
        let key = pmid.isEmpty ? "glkb" : "pmid\(pmid)"
        let authors = reference.authors.compactMap(AuthorName.parse)
        // Field values are escaped here, piece by piece, so the braces that
        // protect a group author's name survive.
        var fields: [(String, String)] = []
        if !authors.isEmpty {
            fields.append(("author", authors.map { $0.bibtex(escaping: escapeBibTeX) }.joined(separator: " and ")))
        }
        fields.append(("title", escapeBibTeX(cleanTitle(reference.title))))
        if let journal = reference.journal, !clean(journal).isEmpty {
            fields.append(("journal", escapeBibTeX(clean(journal))))
        }
        let year = year(from: reference.date)
        if !year.isEmpty { fields.append(("year", year)) }
        if let volume = nonEmpty(reference.volume) { fields.append(("volume", escapeBibTeX(volume))) }
        if let issue = nonEmpty(reference.issue) { fields.append(("number", escapeBibTeX(issue))) }
        if let pages = nonEmpty(reference.pages) {
            fields.append(("pages", escapeBibTeX(pages.replacingOccurrences(of: "-", with: "--"))))
        }
        if let doi = nonEmpty(reference.doi) { fields.append(("doi", escapeBibTeX(doi))) }
        if !pmid.isEmpty { fields.append(("pmid", pmid)) }
        if let url = PubMed.url(for: reference.pmid) ?? reference.url {
            fields.append(("url", escapeBibTeX(url.absoluteString)))
        }
        let body = fields
            .map { "  \($0.0) = {\($0.1)}" }
            .joined(separator: ",\n")
        return "@article{\(key),\n\(body)\n}"
    }

    /// EndNote-compatible RIS record.
    public static func ris(for reference: LiteratureReference) -> String {
        var lines = ["TY  - JOUR"]
        for author in reference.authors.compactMap(AuthorName.parse) {
            lines.append("AU  - \(author.ris)")
        }
        lines.append("TI  - \(cleanTitle(reference.title))")
        if let journal = reference.journal, !clean(journal).isEmpty {
            // T2 is the periodical title for a journal article; JO is an
            // abbreviation field that EndNote files as "Alternate Journal".
            lines.append("T2  - \(clean(journal))")
        }
        let year = year(from: reference.date)
        if !year.isEmpty { lines.append("PY  - \(year)") }
        if let volume = nonEmpty(reference.volume) { lines.append("VL  - \(volume)") }
        if let issue = nonEmpty(reference.issue) { lines.append("IS  - \(issue)") }
        if let pages = nonEmpty(reference.pages) {
            let range = pages.split(separator: "-", maxSplits: 1).map(String.init)
            lines.append("SP  - \(range[0])")
            if range.count == 2 { lines.append("EP  - \(range[1])") }
        }
        if let doi = nonEmpty(reference.doi) { lines.append("DO  - \(doi)") }
        let pmid = clean(reference.pmid)
        if !pmid.isEmpty {
            lines.append("AN  - \(pmid)")
            lines.append("DB  - PubMed")
        }
        if let url = PubMed.url(for: reference.pmid) ?? reference.url {
            lines.append("UR  - \(url.absoluteString)")
        }
        lines.append("ER  - ")
        return lines.joined(separator: "\n")
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
    private static func linked(_ text: String, _ link: URL?) -> Runs { [FormattedCitation.Run(text: text, link: link)] }

    /// Joins the parts of a citation with single spaces, or `separator`.
    private static func joined(_ parts: [Runs], separator: String = " ") -> Runs {
        var result: Runs = []
        for (index, part) in parts.enumerated() {
            if index > 0 { result += plain(separator) }
            result += part
        }
        return result
    }

    // MARK: - Pieces

    /// Extracts a 4-digit year from free-form date text such as
    /// `"2024"`, `"2024 Mar"`, or `"2024-03-12"`.
    private static func year(from date: String?) -> String {
        guard let date else { return "" }
        var digits = ""
        for character in date {
            if character.isNumber {
                digits.append(character)
                if digits.count == 4 { return digits }
            } else {
                digits = ""
            }
        }
        return ""
    }

    private static func harvardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func clean(_ value: String) -> String {
        LiteratureNetworking.clean(value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.map(clean).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The resolver link for a bare DOI, percent-encoding characters a URL
    /// path cannot carry.
    private static func doiURL(_ doi: String) -> URL? {
        doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            .flatMap { URL(string: "https://doi.org/\($0)") }
    }

    /// Page ranges take an en dash in prose styles: "48-61.e6" → "48–61.e6".
    private static func pageRange(_ pages: String) -> String {
        pages.replacingOccurrences(of: "-", with: "\u{2013}")
    }

    /// "pp." for a range or list of pages, "p." for one page or article number.
    private static func pagePrefix(_ pages: String) -> String {
        pages.contains("\u{2013}") || pages.contains(",") ? "pp." : "p."
    }

    /// Titles from PubMed frequently end with a period already; strip it so
    /// style templates control the final punctuation.
    private static func cleanTitle(_ value: String) -> String {
        var title = clean(value)
        while title.hasSuffix(".") { title.removeLast() }
        return title
    }

    /// Journal names in headline case, as every style prints them. PubMed
    /// sometimes lowercases words after the first ("Cell metabolism"), so
    /// each all-lowercase word is capitalized, except short function words
    /// after the first. Words with any capital ("eLife", "mBio", "PLoS ONE",
    /// "JAMA") are kept as written. Article titles are left alone: their
    /// sentence case carries gene and protein names.
    static func journalTitle(_ journal: String) -> String {
        var isFirst = true
        return journal.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            defer { if !word.isEmpty { isFirst = false } }
            let text = String(word)
            guard text.contains(where: \.isLetter), !text.contains(where: \.isUppercase) else { return text }
            if !isFirst, minorJournalWords.contains(text) { return text }
            return text
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { part in
                    guard let index = part.firstIndex(where: \.isLetter) else { return String(part) }
                    return part[..<index] + part[index].uppercased() + part[part.index(after: index)...]
                }
                .joined(separator: "-")
        }.joined(separator: " ")
    }

    private static let minorJournalWords: Set<String> = [
        "a", "an", "the", "and", "or", "nor", "but", "for", "of", "in", "on", "at", "to", "by",
        "with", "from", "as", "via", "per", "de", "des", "du", "la", "le", "les", "et", "der",
        "die", "das", "und", "für", "y", "e", "di",
    ]

    /// A title ending in "?" or "!" keeps that mark instead of gaining a
    /// second stop.
    private static func endsWithTerminalPunctuation(_ title: String) -> Bool {
        title.hasSuffix("?") || title.hasSuffix("!")
    }

    private static func escapeBibTeX(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
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

    /// Accepts "Caelles C", "Caelles CA", "C Caelles", "C A Caelles",
    /// "Caelles, Carme", "Carme Caelles", "J van der Berg", "Smith J Jr",
    /// and group names. Returns nil for an empty string.
    ///
    /// All-capital surnames ("ZHANG Wei", "Smith, JOHN") are recased
    /// ("Zhang", "John"); initials keep their capitals.
    static func parse(_ raw: String) -> AuthorName? {
        let text = LiteratureNetworking.clean(raw)
        guard !text.isEmpty else { return nil }
        if looksCorporate(text) {
            return AuthorName(surname: text, givenNames: [], suffix: nil, isCorporate: true)
        }
        return parsePerson(text)?.recased
    }

    private static func parsePerson(_ text: String) -> AuthorName? {

        if let comma = text.firstIndex(of: ",") {
            // "Surname, Given Names[, Suffix]"
            let surname = text[..<comma].trimmingCharacters(in: .whitespaces)
            var given = text[text.index(after: comma)...]
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map(String.init)
            let suffix = takeSuffix(&given)
            guard !surname.isEmpty else { return nil }
            return AuthorName(surname: surname, givenNames: given, suffix: suffix, isCorporate: false)
        }

        var tokens = text.split(separator: " ").map(String.init)
        let suffix = takeSuffix(&tokens)
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
            // One all-capital word among mixed-case ones is the surname,
            // wherever it stands: "ZHANG Wei", "Wei ZHANG".
            let shouted = tokens.indices.filter { isAllCapitalWord(tokens[$0]) }
            if shouted.count == 1, let index = shouted.first {
                var given = tokens
                let surname = given.remove(at: index)
                return AuthorName(surname: surname, givenNames: given, suffix: suffix, isCorporate: false)
            }
            // Full given names first: "Carme Caelles", "Jean Pierre de la Fontaine"
            var surnameStart = tokens.count - 1
            while surnameStart > 1, isParticle(tokens[surnameStart - 1]) { surnameStart -= 1 }
            return AuthorName(
                surname: tokens[surnameStart...].joined(separator: " "),
                givenNames: Array(tokens[..<surnameStart]), suffix: suffix, isCorporate: false
            )
        }
    }

    /// The name with all-capital words recased: every surname word of two
    /// or more letters, and given names too long to be initials.
    private var recased: AuthorName {
        var name = self
        name.surname = surname
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { Self.isAllCapitalWord(String($0)) || ($0.count >= 2 && Self.isInitialsToken(String($0)))
                ? Self.wordCased(String($0)) : String($0) }
            .joined(separator: " ")
        name.givenNames = givenNames.map { Self.isAllCapitalWord($0) ? Self.wordCased($0) : $0 }
        return name
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
        givenNames.map { Self.spaced(Self.initialLetters(of: $0)) }.joined(separator: " ")
    }

    /// "CA" / "JP"
    private var compactInitials: String {
        givenNames.flatMap { Self.initialLetters(of: $0).flatMap { $0 } }.joined()
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

    /// Four or more letters, all capitals: too long for initials, so a
    /// surname or given name set in capitals ("ZHANG", "O'BRIEN").
    private static func isAllCapitalWord(_ token: String) -> Bool {
        let letters = token.filter(\.isLetter)
        return letters.count > 3 && letters.allSatisfy(\.isUppercase)
    }

    /// "ZHANG" → "Zhang", "O'BRIEN" → "O'Brien", "GARCIA-PEREZ" → "Garcia-Perez".
    private static func wordCased(_ word: String) -> String {
        var result = ""
        var startsPart = true
        for character in word {
            result += startsPart ? character.uppercased() : character.lowercased()
            startsPart = character == "-" || character == "'" || character == "\u{2019}"
        }
        return result
    }

    private static let particles: Set<String> = [
        "van", "von", "vander", "vanden", "de", "der", "den", "del", "della", "delle", "di", "da",
        "do", "dos", "das", "du", "la", "le", "les", "ter", "ten", "af", "av", "zu", "zur",
        "bin", "ibn", "al", "el", "y", "e", "of", "op",
    ]

    /// Particles PubMed also writes capitalized ("Reinaldo S Dos Santos",
    /// "Anne Op de Beeck"). Short or ambiguous ones ("E", "Y", "Le", "Do")
    /// stay lowercase-only so a capitalized middle name is not swallowed.
    private static let capitalizedParticles: Set<String> = [
        "van", "von", "vander", "vanden", "de", "der", "den", "del", "della", "delle", "di", "da",
        "dos", "das", "ter", "ten", "op", "al", "el", "bin", "ibn",
    ]

    private static func isParticle(_ token: String) -> Bool {
        let lower = token.lowercased()
        if token == lower { return particles.contains(token) }
        return token == lower.capitalized && capitalizedParticles.contains(lower)
    }

    private static let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "2nd", "3rd"]

    /// Removes a trailing generational suffix and returns it.
    private static func takeSuffix(_ tokens: inout [String]) -> String? {
        guard tokens.count > 1, let last = tokens.last else { return nil }
        let bare = last.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        let key = bare.lowercased()
        guard suffixes.contains(key) else { return nil }
        // "II"/"III"/"IV" could be initials in a two-token name; require a
        // given name as well before treating them as a suffix.
        if key.hasPrefix("i"), tokens.count < 3 { return nil }
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

    /// Group authors contain digits or an organisational word.
    private static func looksCorporate(_ text: String) -> Bool {
        if text.contains(where: \.isNumber) { return true }
        let lower = text.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init))
        return corporateMarkers.contains { marker in
            marker.contains(" ") ? lower.contains(marker) : words.contains(marker)
        }
    }
}
