import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses the XML that NCBI's `efetch.fcgi?db=pubmed&retmode=xml` returns
/// (a `PubmedArticleSet`) into `ArticleMetadata` records.
public enum PubMedArticleParser {
    public static func parse(_ data: Data) throws -> [ArticleMetadata] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw LiteratureError.malformedResponse("PubMed returned unreadable XML: \(reason)")
        }
        guard delegate.sawArticleSet else {
            throw LiteratureError.malformedResponse("PubMed returned XML without a PubmedArticleSet.")
        }
        return delegate.articles
    }

    /// Splits a MEDLINE date such as "1994 Jul-Aug" or "2000 Spring" into a
    /// year and the remainder.
    static func medlineDate(_ value: String) -> (year: String?, month: String?) {
        let text = LiteratureNetworking.clean(value)
        guard let yearRange = text.range(of: #"\b[0-9]{4}\b"#, options: .regularExpression) else {
            return (nil, text.isEmpty ? nil : text)
        }
        let year = String(text[yearRange])
        var rest = text
        rest.removeSubrange(yearRange)
        let month = LiteratureNetworking.clean(rest)
        return (year, month.isEmpty ? nil : month)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var articles: [ArticleMetadata] = []
        var sawArticleSet = false

        private var path: [String] = []
        private var text = ""
        private var current: ArticleMetadata?
        private var author: ArticleAuthor?
        private var authorIsValid = true
        private var insideTitle = false
        private var elocationType: String?
        private var articleIdType: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            path.append(elementName)
            // Titles carry inline markup (<i>, <sup>): keep collecting text
            // across those child elements instead of resetting.
            if insideTitle { return }
            text = ""
            switch elementName {
            case "PubmedArticleSet":
                sawArticleSet = true
            case "PubmedArticle":
                current = ArticleMetadata(pmid: "")
            case "ArticleTitle" where parent == "Article":
                insideTitle = true
            case "Author":
                author = ArticleAuthor()
                authorIsValid = attributes["ValidYN"] != "N"
            case "ELocationID":
                elocationType = attributes["EIdType"]?.lowercased()
            case "ArticleId":
                articleIdType = attributes["IdType"]?.lowercased()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            defer { path.removeLast() }
            if insideTitle {
                if elementName == "ArticleTitle" {
                    current?.title = clean(text)
                    insideTitle = false
                    text = ""
                }
                return
            }
            let value = clean(text)
            switch elementName {
            case "PMID" where parent == "MedlineCitation":
                current?.pmid = PubMed.canonicalPMID(value) ?? value
            case "Title" where parent == "Journal":
                current?.journalTitle = nonEmpty(value)
            case "ISOAbbreviation" where parent == "Journal":
                current?.journalAbbreviation = nonEmpty(value)
            case "Volume" where parent == "JournalIssue":
                current?.volume = nonEmpty(value)
            case "Issue" where parent == "JournalIssue":
                current?.issue = nonEmpty(value)
            case "Year" where parent == "PubDate":
                current?.year = nonEmpty(value)
            case "Month" where parent == "PubDate":
                current?.month = nonEmpty(value)
            case "Day" where parent == "PubDate":
                current?.day = nonEmpty(value)
            case "MedlineDate" where parent == "PubDate":
                let parsed = PubMedArticleParser.medlineDate(value)
                if current?.year == nil { current?.year = parsed.year }
                if current?.month == nil { current?.month = parsed.month }
            case "MedlinePgn" where parent == "Pagination":
                current?.pages = nonEmpty(value)
            case "ELocationID" where elocationType == "doi":
                // PubmedData's ArticleId is authoritative; this is the fallback.
                if current?.doi == nil { current?.doi = nonEmpty(value) }
            case "ArticleId" where articleIdType == "doi" && path.suffix(3) == ["PubmedData", "ArticleIdList", "ArticleId"]:
                // The article's own identifier list. The DOIs of the works it
                // cites sit under PubmedData/ReferenceList and must not match.
                if let doi = nonEmpty(value) { current?.doi = doi }
            case "LastName" where parent == "Author":
                author?.lastName = nonEmpty(value)
            case "ForeName" where parent == "Author":
                author?.foreName = nonEmpty(value)
            case "Initials" where parent == "Author":
                author?.initials = nonEmpty(value)
            case "Suffix" where parent == "Author":
                author?.suffix = nonEmpty(value)
            case "CollectiveName" where parent == "Author":
                author?.collectiveName = nonEmpty(value)
            case "Author":
                if authorIsValid, let author, author.lastName != nil || author.collectiveName != nil {
                    current?.authors.append(author)
                }
                author = nil
            case "PubmedArticle":
                if let current, !current.pmid.isEmpty { articles.append(current) }
                current = nil
            default:
                break
            }
            text = ""
        }

        /// The element enclosing the one being handled.
        private var parent: String? {
            path.count >= 2 ? path[path.count - 2] : nil
        }

        private func clean(_ value: String) -> String {
            LiteratureNetworking.clean(value)
        }

        private func nonEmpty(_ value: String) -> String? {
            value.isEmpty ? nil : value
        }
    }
}
