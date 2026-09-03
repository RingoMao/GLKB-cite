import Foundation

public enum SelectionCaptureMethod: String, Codable, Hashable, Sendable {
    case accessibility
    case clipboardCompatibility = "clipboard_compatibility"
    case service
}

/// A display-independent rectangle. AppKit adapters can translate this to and from `CGRect`.
public struct ScreenRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Text and source metadata captured from another application.
public struct SelectionContext: Codable, Hashable, Sendable {
    public var selectedText: String
    public var sourceApplicationName: String?
    public var sourceBundleIdentifier: String?
    public var bounds: ScreenRect?
    public var isEditable: Bool
    public var captureMethod: SelectionCaptureMethod
    public var capturedAt: Date

    public init(
        selectedText: String,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        bounds: ScreenRect? = nil,
        isEditable: Bool = false,
        captureMethod: SelectionCaptureMethod = .accessibility,
        capturedAt: Date = Date()
    ) {
        self.selectedText = selectedText
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.bounds = bounds
        self.isEditable = isEditable
        self.captureMethod = captureMethod
        self.capturedAt = capturedAt
    }
}

/// Implemented by the AppKit accessibility adapter, not by the networking layer.
@MainActor
public protocol SelectionProviding: AnyObject {
    func currentSelection() throws -> SelectionContext
}

public struct LiteratureQueryOptions: Codable, Hashable, Sendable {
    public var maxArticles: Int
    public var includeEvidence: Bool
    public var cacheDurationMinutes: Int

    public init(
        maxArticles: Int = 5,
        includeEvidence: Bool = true,
        cacheDurationMinutes: Int = 15
    ) {
        self.maxArticles = maxArticles
        self.includeEvidence = includeEvidence
        self.cacheDurationMinutes = cacheDurationMinutes
    }

    public var normalized: Self {
        Self(
            maxArticles: min(25, max(1, maxArticles)),
            includeEvidence: includeEvidence,
            cacheDurationMinutes: min(60, max(0, cacheDurationMinutes))
        )
    }
}

public struct LiteratureQuery: Codable, Hashable, Sendable {
    public var text: String
    public var options: LiteratureQueryOptions

    public init(
        text: String,
        options: LiteratureQueryOptions = .init()
    ) {
        self.text = text
        self.options = options
    }
}

public struct LiteratureEvidence: Codable, Hashable, Sendable {
    public var quote: String
    public var contextType: String?

    public init(quote: String, contextType: String? = nil) {
        self.quote = quote
        self.contextType = contextType
    }

    enum CodingKeys: String, CodingKey {
        case quote
        case contextType = "context_type"
    }
}

public struct LiteratureReference: Codable, Hashable, Sendable, Identifiable {
    public var pmid: String
    public var title: String
    public var url: URL?
    public var authors: [String]
    public var journal: String?
    public var date: String?
    public var citationCount: Int?
    public var relevanceReason: String?
    public var evidence: [LiteratureEvidence]

    public var id: String { pmid }

    public init(
        pmid: String,
        title: String,
        url: URL? = nil,
        authors: [String] = [],
        journal: String? = nil,
        date: String? = nil,
        citationCount: Int? = nil,
        relevanceReason: String? = nil,
        evidence: [LiteratureEvidence] = []
    ) {
        self.pmid = pmid
        self.title = title
        self.url = url
        self.authors = authors
        self.journal = journal
        self.date = date
        self.citationCount = citationCount
        self.relevanceReason = relevanceReason
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case pmid, title, url, authors, journal, date, evidence
        case citationCount = "citation_count"
        case relevanceReason = "why"
    }
}

public struct LiteratureUsage: Codable, Hashable, Sendable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct LiteratureResult: Codable, Hashable, Sendable {
    public var answer: String
    public var references: [LiteratureReference]
    public var usage: LiteratureUsage?
    public var isCached: Bool
    public var sessionID: String?
    public var invocationID: String?
    public var executionTime: Double?

    public init(
        answer: String = "",
        references: [LiteratureReference] = [],
        usage: LiteratureUsage? = nil,
        isCached: Bool = false,
        sessionID: String? = nil,
        invocationID: String? = nil,
        executionTime: Double? = nil
    ) {
        self.answer = answer
        self.references = references
        self.usage = usage
        self.isCached = isCached
        self.sessionID = sessionID
        self.invocationID = invocationID
        self.executionTime = executionTime
    }
}

public enum LiteratureQueryEvent: Sendable {
    case progress(step: String, content: String?)
    case completed(LiteratureResult)
}
