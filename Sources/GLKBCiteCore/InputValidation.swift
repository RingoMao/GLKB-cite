import Foundation

public enum LiteratureInputValidator {
    public static let minimumCharacters = 10
    public static let maximumCharacters = 1_000

    /// Normalizes whitespace and rejects text that would be unhelpfully short or costly to submit.
    public static func normalize(_ input: String) throws -> String {
        let unescaped = input
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\:", with: ":")
        let normalized = unescaped
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count >= minimumCharacters else {
            throw LiteratureError.invalidInput(
                "Select a complete scientific sentence (at least \(minimumCharacters) characters)."
            )
        }
        guard normalized.count <= maximumCharacters else {
            throw LiteratureError.invalidInput(
                "The selection is \(normalized.count) characters. The GLKB citation endpoint accepts at most \(maximumCharacters) characters."
            )
        }
        return normalized
    }
}
