import Foundation

/// Formats a single `LiteratureReference` in common bibliographic styles.
///
/// GLKB references carry PubMed metadata (authors, journal, year, PMID) but
/// no volume/issue/page fields, so each rendering includes the PMID as the
/// stable locator instead.
public enum CitationFormatter {
    public enum Style: String, CaseIterable, Sendable {
        case mla = "MLA"
        case apa = "APA"
        case chicago = "Chicago"
        case harvard = "Harvard"
        case vancouver = "Vancouver"
    }

    public static func citation(for reference: LiteratureReference, style: Style) -> String {
        let title = cleanTitle(reference.title)
        let journal = clean(reference.journal ?? "")
        let year = year(from: reference.date)
        let pmid = clean(reference.pmid)
        let locator = pmid.isEmpty ? "" : " PubMed ID: \(pmid)."

        switch style {
        case .mla:
            let head = authorList(reference.authors, style: .mla)
            return join([head, "\u{201C}\(title).\u{201D}", journalYear(journal, year, separator: " ")])
                + locator
        case .apa:
            let head = authorList(reference.authors, style: .apa)
            let dated = year.isEmpty ? head : "\(head) (\(year))."
            return join([dated, "\(title).", journal.isEmpty ? "" : "\(journal)."]) + locator
        case .chicago:
            let head = authorList(reference.authors, style: .chicago)
            let tail = journal.isEmpty
                ? (year.isEmpty ? "" : "(\(year)).")
                : "\(journal)\(year.isEmpty ? "." : " (\(year)).")"
            return join([head, "\u{201C}\(title).\u{201D}", tail]) + locator
        case .harvard:
            let head = authorList(reference.authors, style: .harvard)
            let dated = year.isEmpty ? head : "\(head) (\(year))."
            return join([dated, "\(title).", journal.isEmpty ? "" : "\(journal)."]) + locator
        case .vancouver:
            let head = authorList(reference.authors, style: .vancouver)
            return join([head, "\(title).", journalYear(journal, year, separator: ". ") ]) + locator
        }
    }

    /// BibTeX `@article` entry.
    public static func bibtex(for reference: LiteratureReference) -> String {
        let pmid = clean(reference.pmid)
        let key = pmid.isEmpty ? "glkb" : "pmid\(pmid)"
        var fields: [(String, String)] = []
        if !reference.authors.isEmpty {
            fields.append(("author", reference.authors.map(clean).filter { !$0.isEmpty }
                .joined(separator: " and ")))
        }
        fields.append(("title", cleanTitle(reference.title)))
        if let journal = reference.journal, !clean(journal).isEmpty {
            fields.append(("journal", clean(journal)))
        }
        let year = year(from: reference.date)
        if !year.isEmpty { fields.append(("year", year)) }
        if !pmid.isEmpty { fields.append(("pmid", pmid)) }
        if let url = PubMed.url(for: reference.pmid) ?? reference.url {
            fields.append(("url", url.absoluteString))
        }
        let body = fields
            .map { "  \($0.0) = {\(escapeBibTeX($0.1))}" }
            .joined(separator: ",\n")
        return "@article{\(key),\n\(body)\n}"
    }

    /// EndNote-compatible RIS record.
    public static func ris(for reference: LiteratureReference) -> String {
        var lines = ["TY  - JOUR"]
        for author in reference.authors.map(clean) where !author.isEmpty {
            lines.append("AU  - \(author)")
        }
        lines.append("TI  - \(cleanTitle(reference.title))")
        if let journal = reference.journal, !clean(journal).isEmpty {
            lines.append("JO  - \(clean(journal))")
        }
        let year = year(from: reference.date)
        if !year.isEmpty { lines.append("PY  - \(year)") }
        let pmid = clean(reference.pmid)
        if !pmid.isEmpty { lines.append("AN  - \(pmid)") }
        if let url = PubMed.url(for: reference.pmid) ?? reference.url {
            lines.append("UR  - \(url.absoluteString)")
        }
        lines.append("ER  - ")
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private static func authorList(_ authors: [String], style: Style) -> String {
        let cleaned = authors.map(clean).filter { !$0.isEmpty }
        guard let first = cleaned.first else { return "" }
        let list: String
        switch style {
        case .vancouver:
            let shown = cleaned.prefix(6).joined(separator: ", ")
            list = cleaned.count > 6 ? "\(shown), et al" : shown
        default:
            if cleaned.count == 1 {
                list = first
            } else if cleaned.count == 2 {
                list = "\(first), \(cleaned[1])"
            } else {
                list = "\(first), et al"
            }
        }
        return list.hasSuffix(".") ? list : "\(list)."
    }

    private static func journalYear(_ journal: String, _ year: String, separator: String) -> String {
        switch (journal.isEmpty, year.isEmpty) {
        case (false, false): return "\(journal)\(separator)\(year)."
        case (false, true): return "\(journal)."
        case (true, false): return "\(year)."
        case (true, true): return ""
        }
    }

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

    private static func join(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
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

    private static func escapeBibTeX(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }
}
