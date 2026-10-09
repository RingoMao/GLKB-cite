import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum LiteratureNetworking {
    /// Longest server-supplied error text that is surfaced to the user.
    static let maximumServerMessageLength = 200

    static func ephemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // The bundled app gets this floor from App Transport Security; the
        // library must not depend on being hosted by that app.
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }

    /// A short, printable message from a JSON error body, or nil.
    static func serverMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else { return nil }

        for key in ["detail", "message", "error"] {
            if let message = dictionary[key] as? String {
                let cleaned = sanitize(message)
                if !cleaned.isEmpty { return cleaned }
            }
            if let entries = dictionary[key] as? [[String: Any]] {
                let messages = entries.compactMap { entry -> String? in
                    guard let message = entry["msg"] as? String else { return nil }
                    let cleaned = clean(message)
                    return cleaned.isEmpty ? nil : cleaned
                }
                if !messages.isEmpty { return sanitize(messages.joined(separator: "; ")) }
            }
        }
        return nil
    }

    /// Collapses whitespace runs to single spaces.
    static func clean(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// `clean`, with control characters removed and a length cap, for text
    /// that comes from the server and is shown to the user.
    static func sanitize(_ value: String) -> String {
        let printable = String(value.unicodeScalars.filter { scalar in
            !(scalar.properties.generalCategory == .control) || scalar == " "
        })
        let cleaned = clean(printable)
        guard cleaned.count > maximumServerMessageLength else { return cleaned }
        return String(cleaned.prefix(maximumServerMessageLength - 1)) + "…"
    }
}
