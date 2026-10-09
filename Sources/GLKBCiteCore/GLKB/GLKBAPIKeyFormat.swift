import Foundation

/// Validation shared by the Keychain store and the backend: a key is `glkb_`
/// followed by URL-safe ASCII characters, on one line. A key pasted from a
/// wrapped email or PDF with an embedded line break would otherwise be sent
/// as an empty `Authorization` header and reported back as "rejected".
public enum GLKBAPIKeyFormat {
    public static let prefix = "glkb_"

    /// The trimmed key when it is well-formed, nil otherwise.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.count > prefix.count else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let body = trimmed.dropFirst(prefix.count)
        guard body.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { return nil }
        return trimmed
    }
}
