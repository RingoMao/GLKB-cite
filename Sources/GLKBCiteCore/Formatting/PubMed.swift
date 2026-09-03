import Foundation

public enum PubMed {
    public static func url(for pmid: String) -> URL? {
        let normalized = pmid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(normalized)/")
    }

    public static func urls(for references: [LiteratureReference]) -> [URL] {
        var seen = Set<String>()
        return references.compactMap { reference in
            let pmid = reference.pmid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(pmid).inserted else { return nil }
            return url(for: pmid)
        }
    }

    /// One native PubMed results page for every valid, unique returned PMID.
    public static func searchURL(for references: [LiteratureReference]) -> URL? {
        var seen = Set<String>()
        let pmids = references.compactMap { reference -> String? in
            let pmid = reference.pmid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard url(for: pmid) != nil, seen.insert(pmid).inserted else { return nil }
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
