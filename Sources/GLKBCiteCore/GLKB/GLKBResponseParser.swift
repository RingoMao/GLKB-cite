import Foundation

public enum GLKBResponseParser {
    /// Citation counts above this are not plausible for a PubMed article and
    /// are treated as absent rather than displayed.
    static let maximumCitationCount = 10_000_000

    public static func parse(
        _ data: Data,
        options: LiteratureQueryOptions = .init()
    ) throws -> LiteratureResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LiteratureError.malformedResponse("The body is not valid JSON.")
        }

        guard let dictionary = object as? [String: Any] else {
            throw LiteratureError.malformedResponse("Expected a JSON object.")
        }
        guard let status = dictionary["status"] as? String,
              status == "ok" || status == "no_results" else {
            throw LiteratureError.malformedResponse("Expected status to be ok or no_results.")
        }

        let answer = status == "no_results"
            ? "GLKB found no supporting references for this sentence."
            : firstString(in: dictionary, keys: ["answer", "response", "content"])
        let rawReferences = dictionary["references"] as? [Any] ?? []
        let normalizedOptions = options.normalized
        var references: [LiteratureReference] = []
        var seenPMIDs = Set<String>()

        // Scan a bounded number of raw entries: the loop stops after
        // `maxArticles` valid references, so without a cap a response of
        // millions of invalid entries would be scanned in full.
        for rawReference in rawReferences.prefix(Self.maximumScannedReferences) {
            guard let reference = normalizeReference(rawReference) else { continue }
            guard !seenPMIDs.contains(reference.pmid) else { continue }
            seenPMIDs.insert(reference.pmid)
            references.append(reference)
            if references.count == normalizedOptions.maxArticles { break }
        }

        if status == "ok", references.isEmpty {
            throw LiteratureError.malformedResponse("GLKB returned status ok without usable references.")
        }
        if status == "no_results", !references.isEmpty {
            throw LiteratureError.malformedResponse("GLKB returned no_results with references.")
        }

        let diagnostics = dictionary["diagnostics"] as? [String: Any]
        let elapsedMilliseconds = diagnostics.flatMap { double($0["elapsed_ms"]) }
        return LiteratureResult(
            answer: answer,
            references: references,
            executionTime: elapsedMilliseconds.map { $0 / 1_000 }
        )
    }

    static let maximumScannedReferences = 500

    private static func normalizeReference(_ value: Any) -> LiteratureReference? {
        if let array = value as? [Any] {
            let title = valueAt(array, 0).map(string) ?? ""
            let urlString = valueAt(array, 1).map(string) ?? ""
            guard !title.isEmpty, let pmid = pmid(from: urlString) else { return nil }
            return LiteratureReference(
                pmid: pmid,
                title: title,
                url: PubMed.url(for: pmid),
                authors: stringArray(valueAt(array, 5)),
                journal: nilIfEmpty(valueAt(array, 4).map(string) ?? ""),
                date: nilIfEmpty(valueAt(array, 3).map(string) ?? ""),
                citationCount: integer(valueAt(array, 2)),
                evidence: []
            )
        }

        guard let dictionary = value as? [String: Any] else { return nil }
        let urlString = firstString(in: dictionary, keys: ["url"])
        // Only PubMed identifiers name a reference; a generic `id` could be a
        // database row id and would be linked as if it were a PMID.
        let pmidValue = firstString(in: dictionary, keys: ["pmid", "pubmedid"])
        let pmid = PubMed.canonicalPMID(pmidValue) ?? self.pmid(from: urlString)
        let title = firstString(in: dictionary, keys: ["title"])
        guard let pmid, !title.isEmpty else { return nil }

        let evidence = (dictionary["evidence"] as? [Any] ?? []).compactMap(normalizeEvidence)
        return LiteratureReference(
            pmid: pmid,
            title: title,
            // Always the canonical PubMed URL; a server-supplied URL is never
            // opened from the app.
            url: PubMed.url(for: pmid),
            authors: stringArray(dictionary["authors"]),
            journal: nilIfEmpty(firstString(in: dictionary, keys: ["journal"])),
            date: nilIfEmpty(firstString(in: dictionary, keys: ["date", "year"])),
            citationCount: integer(dictionary["n_citation"]) ?? integer(dictionary["citation_count"]),
            relevanceReason: nilIfEmpty(firstString(in: dictionary, keys: ["why"])),
            evidence: evidence
        )
    }

    private static func normalizeEvidence(_ value: Any) -> LiteratureEvidence? {
        if let quote = value as? String {
            let cleaned = clean(quote)
            return cleaned.isEmpty ? nil : LiteratureEvidence(quote: cleaned)
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        let quote = firstString(in: dictionary, keys: ["quote"])
        guard !quote.isEmpty else { return nil }
        return LiteratureEvidence(
            quote: quote,
            contextType: nilIfEmpty(firstString(in: dictionary, keys: ["context_type", "contextType"]))
        )
    }

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            let result = string(value)
            if !result.isEmpty { return result }
        }
        return ""
    }

    private static func string(_ value: Any) -> String {
        switch value {
        case let string as String:
            return clean(string)
        case let number as NSNumber:
            // JSON true/false arrive as NSNumber; "1"/"0" is never the
            // intended text.
            guard !isBoolean(number) else { return "" }
            return clean(number.stringValue)
        default:
            return ""
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func clean(_ string: String) -> String {
        LiteratureNetworking.clean(string)
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).map(string).filter { !$0.isEmpty }
    }

    /// A non-negative, plausible integer, or nil. Out-of-range numbers
    /// (`1.5e20`, 30-digit decimals) would otherwise saturate or wrap into
    /// garbage counts.
    private static func integer(_ value: Any?) -> Int? {
        let candidate: Double?
        switch value {
        case let number as NSNumber:
            guard !isBoolean(number) else { return nil }
            candidate = number.doubleValue
        case let string as String:
            candidate = Double(string.trimmingCharacters(in: .whitespaces))
        default:
            candidate = nil
        }
        guard let candidate, candidate.isFinite, candidate >= 0,
              candidate <= Double(maximumCitationCount),
              candidate == candidate.rounded() else { return nil }
        return Int(candidate)
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: isBoolean(number) ? nil : number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private static func valueAt(_ array: [Any], _ index: Int) -> Any? {
        array.indices.contains(index) ? array[index] : nil
    }

    private static func pmid(from url: String) -> String? {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"pubmed\.ncbi\.nlm\.nih\.gov/([0-9]+)"#,
                options: [.caseInsensitive]
            ),
            let match = expression.firstMatch(
                in: url,
                range: NSRange(url.startIndex..., in: url)
            ),
            let range = Range(match.range(at: 1), in: url)
        else { return nil }
        return PubMed.canonicalPMID(String(url[range]))
    }
}
