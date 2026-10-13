import Foundation

/// One author as PubMed records it: structured name parts rather than the
/// single free-form string GLKB returns.
public struct ArticleAuthor: Codable, Hashable, Sendable {
    public var lastName: String?
    public var foreName: String?
    public var initials: String?
    public var suffix: String?
    /// A group author ("GBD 2019 Collaborators"); the name parts are nil.
    public var collectiveName: String?

    public init(
        lastName: String? = nil,
        foreName: String? = nil,
        initials: String? = nil,
        suffix: String? = nil,
        collectiveName: String? = nil
    ) {
        self.lastName = lastName
        self.foreName = foreName
        self.initials = initials
        self.suffix = suffix
        self.collectiveName = collectiveName
    }
}

/// A date as PubMed splits it; any part may be missing, and `month` may be
/// a name ("Jul"), a number ("07"), a season ("Spring") or a range.
public struct ArticleDate: Codable, Hashable, Sendable {
    public var year: String?
    public var month: String?
    public var day: String?

    public init(year: String? = nil, month: String? = nil, day: String? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// What kind of record PubMed holds for a PMID.
public enum ArticleKind: String, Codable, Hashable, Sendable {
    case journalArticle
    /// A chapter of a book on the NCBI Bookshelf (StatPearls, GeneReviews).
    case bookChapter
}

/// Bibliographic details of one PubMed record, fetched by PMID. GLKB's
/// references carry only a title, free-form authors, a journal name and a
/// year; a complete citation also needs the volume, issue, pages, DOI, the
/// journal's standard abbreviation, and structured author names — or, for a
/// book chapter, the book, its editors and publisher.
public struct ArticleMetadata: Codable, Hashable, Sendable {
    public var pmid: String
    public var kind: ArticleKind
    public var title: String?
    public var authors: [ArticleAuthor]
    public var journalTitle: String?
    /// NLM / ISO abbreviation, e.g. "Sci Rep".
    public var journalAbbreviation: String?
    public var year: String?
    /// As PubMed gives it: usually "Jul", sometimes "07", a season or a range.
    public var month: String?
    public var day: String?
    public var volume: String?
    public var issue: String?
    /// MEDLINE pagination as given, e.g. "220-3", "2461", "e101456".
    public var pages: String?
    /// An article's e-locator ("e85096", "arXiv:2610.03640v1") when the
    /// record has no pagination.
    public var articleNumber: String?
    public var doi: String?
    /// PubMed's publication types ("Journal Article", "Retracted
    /// Publication", "Preprint", …).
    public var publicationTypes: [String]
    // Book chapters only.
    public var bookTitle: String?
    public var editors: [ArticleAuthor]
    public var publisher: String?
    public var publisherLocation: String?
    /// NCBI Bookshelf accession ("NBK625053"), which names the chapter's URL.
    public var bookshelfID: String?
    /// When the chapter was last revised (StatPearls, GeneReviews).
    public var contributionDate: ArticleDate?

    public init(
        pmid: String,
        kind: ArticleKind = .journalArticle,
        title: String? = nil,
        authors: [ArticleAuthor] = [],
        journalTitle: String? = nil,
        journalAbbreviation: String? = nil,
        year: String? = nil,
        month: String? = nil,
        day: String? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pages: String? = nil,
        articleNumber: String? = nil,
        doi: String? = nil,
        publicationTypes: [String] = [],
        bookTitle: String? = nil,
        editors: [ArticleAuthor] = [],
        publisher: String? = nil,
        publisherLocation: String? = nil,
        bookshelfID: String? = nil,
        contributionDate: ArticleDate? = nil
    ) {
        self.pmid = pmid
        self.kind = kind
        self.title = title
        self.authors = authors
        self.journalTitle = journalTitle
        self.journalAbbreviation = journalAbbreviation
        self.year = year
        self.month = month
        self.day = day
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.articleNumber = articleNumber
        self.doi = doi
        self.publicationTypes = publicationTypes
        self.bookTitle = bookTitle
        self.editors = editors
        self.publisher = publisher
        self.publisherLocation = publisherLocation
        self.bookshelfID = bookshelfID
        self.contributionDate = contributionDate
    }

    /// PubMed lists a retraction notice for this article.
    public var isRetracted: Bool { publicationTypes.contains("Retracted Publication") }

    /// A preprint (arXiv, medRxiv, bioRxiv), not peer reviewed.
    public var isPreprint: Bool { publicationTypes.contains("Preprint") }

    /// The chapter's page on the NCBI Bookshelf.
    public var bookshelfURL: URL? {
        guard let id = bookshelfID, !id.isEmpty,
              id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return URL(string: "https://www.ncbi.nlm.nih.gov/books/\(id)/")
    }
}
