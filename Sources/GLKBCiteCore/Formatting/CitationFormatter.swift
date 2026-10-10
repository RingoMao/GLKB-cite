import Foundation

/// Formats a single `LiteratureReference` in common bibliographic styles.
///
/// GLKB references carry PubMed metadata (authors, title, journal, year and
/// PMID) but no volume, issue, page or DOI fields, so each style ends with
/// the locator it gives an online article without those fields: the PubMed
/// URL (MLA, APA, Chicago, Harvard) or the PMID (Vancouver).
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
        let authors = reference.authors.compactMap(AuthorName.parse)
        let title = displayTitle(reference.title)
        let titleSentence = endsWithTerminalPunctuation(title) ? title : "\(title)."
        let journal = clean(reference.journal ?? "")
        let year = year(from: reference.date)
        let pmid = PubMed.canonicalPMID(reference.pmid) ?? ""
        let pubmedURL = PubMed.url(for: reference.pmid)
        let url = (pubmedURL ?? webURL(reference.url))?.absoluteString ?? ""

        switch style {
        case .mla:
            // Author. "Title." Journal, Year. Database, URL.
            var parts: [String] = []
            if let head = authorBlock(authors, style: style) { parts.append(head) }
            parts.append("\u{201C}\(titleSentence)\u{201D}")
            parts += container(journal, year, separator: ", ", undated: nil)
            if !url.isEmpty {
                // The database name belongs only to a PubMed locator.
                parts.append(pubmedURL != nil ? "PubMed, \(url)." : "\(url).")
            }
            return parts.joined(separator: " ")

        case .apa:
            // Author, A. A., & Author, B. B. (Year). Title. Journal. URL
            let date = year.isEmpty ? "n.d." : year
            var parts: [String] = []
            if let head = authorBlock(authors, style: style) {
                parts += [head, "(\(date)).", titleSentence]
            } else {
                parts += [titleSentence, "(\(date))."]
            }
            if !journal.isEmpty { parts.append("\(journal).") }
            if !url.isEmpty { parts.append(url) }
            return parts.joined(separator: " ")

        case .chicago:
            // Author, A., B. Author, and C. Author. "Title." Journal, Year. URL.
            var parts: [String] = []
            if let head = authorBlock(authors, style: style) { parts.append(head) }
            parts.append("\u{201C}\(titleSentence)\u{201D}")
            parts += container(journal, year, separator: ", ", undated: "n.d.")
            if !url.isEmpty { parts.append("\(url).") }
            return parts.joined(separator: " ")

        case .harvard:
            // Author, A., Author, B. and Author, C. (Year) 'Title', Journal.
            // Available at: URL (Accessed: Day Month Year).
            let date = year.isEmpty ? "no date" : year
            let quotedTitle = "\u{2018}\(title)\u{2019}"
            let titleStop = endsWithTerminalPunctuation(title) ? "" : "."
            var head: String
            if let authorsText = authorBlock(authors, style: style) {
                head = "\(authorsText) (\(date)) \(quotedTitle)"
                head += journal.isEmpty ? titleStop : ", \(journal)."
            } else {
                head = "\(quotedTitle) (\(date))"
                head += journal.isEmpty ? "." : " \(journal)."
            }
            guard !url.isEmpty else { return head }
            return "\(head) Available at: \(url) (Accessed: \(harvardDate(accessDate)))."

        case .vancouver:
            // Author AA, Author BB. Title. Journal. Year. PMID: n.
            var parts: [String] = []
            if let head = authorBlock(authors, style: style) { parts.append(head) }
            parts.append(titleSentence)
            parts += container(journal, year, separator: ". ", undated: nil)
            if !pmid.isEmpty { parts.append("PMID: \(pmid).") }
            return parts.joined(separator: " ")
        }
    }

    /// BibTeX `@article` entry.
    public static func bibtex(for reference: LiteratureReference) -> String {
        let pmid = PubMed.canonicalPMID(reference.pmid) ?? ""
        let authors = reference.authors.compactMap(AuthorName.parse)
        // Field values are escaped here, piece by piece, so the braces that
        // protect a group author's name survive.
        var fields: [(String, String)] = []
        if !authors.isEmpty {
            fields.append(("author", authors.map { $0.bibtex(escaping: escapeBibTeX) }.joined(separator: " and ")))
        }
        // The inner braces keep the title's capitalisation as written; most
        // BibTeX styles lower-case an unprotected title.
        fields.append(("title", "{\(escapeBibTeX(displayTitle(reference.title)))}"))
        if let journal = reference.journal, !clean(journal).isEmpty {
            fields.append(("journal", escapeBibTeX(clean(journal))))
        }
        let year = year(from: reference.date)
        if !year.isEmpty { fields.append(("year", year)) }
        if !pmid.isEmpty { fields.append(("pmid", pmid)) }
        if let url = PubMed.url(for: reference.pmid) ?? webURL(reference.url) {
            // URLs are not TeX-escaped: the url/hyperref packages read the
            // field verbatim, and an escaped "%" would break the link.
            fields.append(("url", url.absoluteString.filter { $0 != "{" && $0 != "}" && !$0.isWhitespace }))
        }
        let body = fields
            .map { "  \($0.0) = {\($0.1)}" }
            .joined(separator: ",\n")
        return "@article{\(bibtexKey(for: reference)),\n\(body)\n}"
    }

    /// EndNote-compatible RIS record: CRLF line ends and a terminating
    /// newline, as the RIS specification and EndNote's importer expect.
    public static func ris(for reference: LiteratureReference) -> String {
        var lines = ["TY  - JOUR"]
        for author in reference.authors.compactMap(AuthorName.parse) {
            lines.append("AU  - \(author.ris)")
        }
        lines.append("TI  - \(displayTitle(reference.title))")
        if let journal = reference.journal, !clean(journal).isEmpty {
            // T2 is the periodical title for a journal article; JO is an
            // abbreviation field that EndNote files as "Alternate Journal".
            lines.append("T2  - \(clean(journal))")
        }
        let year = year(from: reference.date)
        if !year.isEmpty { lines.append("PY  - \(year)") }
        let pmid = PubMed.canonicalPMID(reference.pmid) ?? ""
        if !pmid.isEmpty {
            lines.append("AN  - \(pmid)")
            lines.append("DB  - PubMed")
        }
        if let url = PubMed.url(for: reference.pmid) ?? webURL(reference.url) {
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

    /// Journal and year as one element, in the style's punctuation, or
    /// nothing when both are missing. `undated` is the placeholder a style
    /// uses for a journal without a year ("n.d."), nil to omit the year.
    private static func container(
        _ journal: String, _ year: String, separator: String, undated: String?
    ) -> [String] {
        switch (journal.isEmpty, year.isEmpty) {
        case (false, false): return ["\(journal)\(separator)\(year)."]
        case (false, true):
            guard let undated else { return ["\(journal)."] }
            return ["\(journal)\(separator)\(undated)\(undated.hasSuffix(".") ? "" : ".")"]
        case (true, false): return ["\(year)."]
        case (true, true): return []
        }
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

    private static func harvardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func clean(_ value: String) -> String {
        LiteratureNetworking.clean(value)
    }

    /// Titles from PubMed frequently end with a period already; strip it so
    /// style templates control the final punctuation.
    private static func cleanTitle(_ value: String) -> String {
        var title = clean(value)
        while title.hasSuffix(".") { title.removeLast() }
        return clean(title)
    }

    private static func displayTitle(_ value: String) -> String {
        let title = cleanTitle(value)
        return title.isEmpty ? untitledPlaceholder : title
    }

    /// A title ending in "?" or "!" keeps that mark instead of gaining a
    /// second stop.
    private static func endsWithTerminalPunctuation(_ title: String) -> Bool {
        title.hasSuffix("?") || title.hasSuffix("!")
    }

    /// Only web URLs are cited; a reference built by hand could carry any
    /// scheme.
    private static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
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
