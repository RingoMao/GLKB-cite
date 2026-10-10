import Foundation

public enum PubMed {
    /// The PMID in canonical form — ASCII digits, no leading zeros — or nil
    /// for anything that is not a PubMed identifier. Unicode digits (Arabic-
    /// Indic, fullwidth, superscripts, Roman numerals) are not accepted even
    /// though `Character.isNumber` would call them numbers.
    public static func canonicalPMID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII && ("0" ... "9").contains($0) })
        else { return nil }
        let significant = trimmed.drop(while: { $0 == "0" })
        guard !significant.isEmpty else { return nil }
        return String(significant)
    }

    public static func url(for pmid: String) -> URL? {
        guard let canonical = canonicalPMID(pmid) else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(canonical)/")
    }

    public static func urls(for references: [LiteratureReference]) -> [URL] {
        var seen = Set<String>()
        return references.compactMap { reference in
            guard let pmid = canonicalPMID(reference.pmid), seen.insert(pmid).inserted else { return nil }
            return url(for: pmid)
        }
    }

    /// One native PubMed results page for every valid, unique returned PMID.
    public static func searchURL(for references: [LiteratureReference]) -> URL? {
        var seen = Set<String>()
        let pmids = references.compactMap { reference -> String? in
            guard let pmid = canonicalPMID(reference.pmid), seen.insert(pmid).inserted else { return nil }
            return pmid
        }
        guard !pmids.isEmpty else { return nil }

        var components = URLComponents(string: "https://pubmed.ncbi.nlm.nih.gov/")
        components?.queryItems = [
            URLQueryItem(name: "term", value: pmids.joined(separator: " "))
        ]
        return components?.url
    }
}
