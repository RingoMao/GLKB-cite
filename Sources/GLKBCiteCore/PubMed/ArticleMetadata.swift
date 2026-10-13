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

/// Bibliographic details of one PubMed record, fetched by PMID. GLKB's
/// references carry only a title, free-form authors, a journal name and a
/// year; a complete citation also needs the volume, issue, pages, DOI, the
/// journal's standard abbreviation, and structured author names.
public struct ArticleMetadata: Codable, Hashable, Sendable {
    public var pmid: String
    public var title: String?
    public var authors: [ArticleAuthor]
    public var journalTitle: String?
    /// NLM / ISO abbreviation, e.g. "Sci Rep".
    public var journalAbbreviation: String?
    public var year: String?
    /// As PubMed gives it: usually "Jul", sometimes "07" or a season.
    public var month: String?
    public var day: String?
    public var volume: String?
    public var issue: String?
    /// MEDLINE pagination as given, e.g. "220-3", "2461", "e101456".
    public var pages: String?
    public var doi: String?

    public init(
        pmid: String,
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
        doi: String? = nil
    ) {
        self.pmid = pmid
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
        self.doi = doi
    }
}
