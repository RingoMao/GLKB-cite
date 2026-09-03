import Foundation

public struct GLKBRequest: Codable, Equatable, Sendable {
    public var text: String
    public var maxReferences: Int

    public init(text: String, maxReferences: Int) {
        self.text = text
        self.maxReferences = maxReferences
    }

    enum CodingKeys: String, CodingKey {
        case text
        case maxReferences = "max_references"
    }
}

public enum GLKBRequestBuilder {
    public static func make(
        selectedText: String,
        options: LiteratureQueryOptions = .init()
    ) throws -> GLKBRequest {
        let text = try LiteratureInputValidator.normalize(selectedText)
        let options = options.normalized
        return GLKBRequest(
            text: text,
            maxReferences: options.maxArticles
        )
    }
}
