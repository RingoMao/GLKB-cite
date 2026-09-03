import Foundation

public enum GLKBResponseParser {
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

        for rawReference in rawReferences {
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

    private static func normalizeReference(_ value: Any) -> LiteratureReference? {
        if let array = value as? [Any] {
            let title = valueAt(array, 0).map(string) ?? ""
            let urlString = valueAt(array, 1).map(string) ?? ""
            let pmid = pmid(from: urlString)
            guard !title.isEmpty, !pmid.isEmpty else { return nil }
            return LiteratureReference(
                pmid: pmid,
                title: title,
                url: normalizedURL(urlString, pmid: pmid),
                authors: stringArray(valueAt(array, 5)),
                journal: nilIfEmpty(valueAt(array, 4).map(string) ?? ""),
                date: nilIfEmpty(valueAt(array, 3).map(string) ?? ""),
                citationCount: integer(valueAt(array, 2)),
                evidence: []
            )
        }

        guard let dictionary = value as? [String: Any] else { return nil }
        let urlString = firstString(in: dictionary, keys: ["url"])
        let pmidValue = firstString(in: dictionary, keys: ["pmid", "pubmedid", "id"])
        let pmid = pmidValue.isEmpty ? pmid(from: urlString) : pmidValue
        let title = firstString(in: dictionary, keys: ["title"])
        guard !pmid.isEmpty,
              pmid.allSatisfy(\.isNumber),
              !title.isEmpty else { return nil }

        let evidence = (dictionary["evidence"] as? [Any] ?? []).compactMap(normalizeEvidence)
        return LiteratureReference(
            pmid: pmid,
            title: title,
            url: normalizedURL(urlString, pmid: pmid),
            authors: stringArray(dictionary["authors"]),
            journal: nilIfEmpty(firstString(in: dictionary, keys: ["journal"])),
            date: nilIfEmpty(firstString(in: dictionary, keys: ["date", "year"])),
            citationCount: integer(dictionary["n_citation"] ?? dictionary["citation_count"]),
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
            return clean(number.stringValue)
        default:
            return ""
        }
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

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private static func valueAt(_ array: [Any], _ index: Int) -> Any? {
        array.indices.contains(index) ? array[index] : nil
    }

    private static func pmid(from url: String) -> String {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"pubmed\.ncbi\.nlm\.nih\.gov/(\d+)"#,
                options: [.caseInsensitive]
            ),
            let match = expression.firstMatch(
                in: url,
                range: NSRange(url.startIndex..., in: url)
            ),
            let range = Range(match.range(at: 1), in: url)
        else { return "" }
        return String(url[range])
    }

    private static func normalizedURL(_ value: String, pmid: String) -> URL? {
        if let pubMedURL = PubMed.url(for: pmid) {
            return pubMedURL
        }
        if let url = URL(string: value),
           url.scheme?.lowercased() == "https",
           url.host != nil {
            return url
        }
        return nil
    }

}
