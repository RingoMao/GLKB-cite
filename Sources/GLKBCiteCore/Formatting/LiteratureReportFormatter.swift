import Foundation

public enum LiteratureReportFormatter {
    public static func plainText(
        _ result: LiteratureResult,
        includeEvidence: Bool = true
    ) -> String {
        var lines: [String] = []
        let heading = "GLKB citation recommendations"
        lines.append("\(heading) (\(result.references.count))")

        let answer = clean(result.answer)
        if !answer.isEmpty {
            lines.append("")
            lines.append(answer)
        }

        for (index, reference) in result.references.enumerated() {
            lines.append("")
            lines.append("\(index + 1). \(clean(reference.title))")
            let metadata = formatMetadata(reference)
            if !metadata.isEmpty { lines.append("   \(metadata)") }
            if let url = PubMed.url(for: reference.pmid) {
                lines.append("   PMID: \(reference.pmid) — \(url.absoluteString)")
            } else {
                lines.append("   PMID: \(reference.pmid)")
            }
            if includeEvidence, let quote = reference.evidence.first?.quote, !clean(quote).isEmpty {
                lines.append("   Evidence: “\(truncate(clean(quote), maximum: 360))”")
            }
        }

        lines.append("")
        lines.append(disclaimer)
        return lines.joined(separator: "\n")
    }

    public static func html(
        _ result: LiteratureResult,
        includeEvidence: Bool = true
    ) -> String {
        let title = "GLKB citation recommendations"
        let answer = clean(result.answer)
        let answerHTML = answer.isEmpty ? "" : "<p>\(escapeHTML(answer))</p>"
        let items = result.references.map { reference in
            let metadata = formatMetadata(reference)
            let url = PubMed.url(for: reference.pmid)
            let pmidHTML: String
            if let url {
                pmidHTML = "<a href=\"\(escapeHTML(url.absoluteString))\">PMID \(escapeHTML(reference.pmid))</a>"
            } else {
                pmidHTML = "PMID \(escapeHTML(reference.pmid))"
            }
            let evidenceHTML: String
            if includeEvidence,
               let quote = reference.evidence.first?.quote,
               !clean(quote).isEmpty {
                evidenceHTML = "<blockquote>\(escapeHTML(truncate(clean(quote), maximum: 360)))</blockquote>"
            } else {
                evidenceHTML = ""
            }
            return [
                "<li>",
                "<strong>\(escapeHTML(clean(reference.title)))</strong>",
                metadata.isEmpty ? "" : "<div>\(escapeHTML(metadata))</div>",
                "<div>\(pmidHTML)</div>",
                evidenceHTML,
                "</li>",
            ].joined()
        }.joined()

        return [
            "<div style=\"font-family:-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;line-height:1.45\">",
            "<h2>\(escapeHTML(title)) (\(result.references.count))</h2>",
            answerHTML,
            "<ol>\(items)</ol>",
            "<p><small>\(escapeHTML(disclaimer))</small></p>",
            "</div>",
        ].joined()
    }

    private static func formatMetadata(_ reference: LiteratureReference) -> String {
        let authors = reference.authors.map(clean).filter { !$0.isEmpty }
        let authorText: String
        if authors.count <= 3 {
            authorText = authors.joined(separator: ", ")
        } else {
            authorText = authors.prefix(3).joined(separator: ", ") + ", et al."
        }
        return [authorText, reference.journal.map(clean), reference.date.map(clean)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func clean(_ value: String) -> String {
        LiteratureNetworking.clean(value)
    }

    private static let disclaimer =
        "Generated from GLKB/PubMed evidence. Verify each source before citing."

    private static func truncate(_ value: String, maximum: Int) -> String {
        guard value.count > maximum else { return value }
        let prefix = String(value.prefix(maximum - 1))
        if let finalSpace = prefix.lastIndex(of: " "),
           prefix.distance(from: prefix.startIndex, to: finalSpace) >= Int(Double(maximum) * 0.7) {
            return String(prefix[..<finalSpace]) + "…"
        }
        return prefix + "…"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
