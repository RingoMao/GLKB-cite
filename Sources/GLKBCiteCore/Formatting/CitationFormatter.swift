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
    }

    /// - Parameter accessDate: the date in Harvard's "Accessed" note. It
    ///   defaults to now and is injectable for deterministic tests.
    public static func citation(
        for reference: LiteratureReference,
        style: Style,
        accessDate: Date = Date()
    ) -> String {
        let authors = reference.authors.compactMap(AuthorName.parse)
        let title = cleanTitle(reference.title)
        let titleSentence = endsWithTerminalPunctuation(title) ? title : "\(title)."
        let journal = clean(reference.journal ?? "")
        let year = year(from: reference.date)
        let pmid = clean(reference.pmid)
        let url = (PubMed.url(for: reference.pmid) ?? reference.url)?.absoluteString ?? ""

        switch style {
        case .mla:
            // Author. "Title." Journal, Year. Database, URL.
            var parts: [String] = []
            if let head = authorBlock(authors, style: style) { parts.append(head) }
            parts.append("\u{201C}\(titleSentence)\u{201D}")
            parts += container(journal, year, separator: ", ", undated: nil)
            if !url.isEmpty { parts.append("PubMed, \(url).") }
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

    /// Titles from PubMed frequently end with a period already; strip it so
    /// style templates control the final punctuation.
    private static func cleanTitle(_ value: String) -> String {
        var title = clean(value)
        while title.hasSuffix(".") { title.removeLast() }
        return title
    }

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
    static func parse(_ raw: String) -> AuthorName? {
        let text = LiteratureNetworking.clean(raw)
        guard !text.isEmpty else { return nil }
        if looksCorporate(text) {
            return AuthorName(surname: text, givenNames: [], suffix: nil, isCorporate: true)
        }

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

    private static func isParticle(_ token: String) -> Bool {
        token == token.lowercased() && particles.contains(token)
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
