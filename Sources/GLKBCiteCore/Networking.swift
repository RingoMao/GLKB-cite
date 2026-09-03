import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum LiteratureNetworking {
    static func ephemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    static func serverMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else { return nil }

        for key in ["detail", "message", "error"] {
            if let message = dictionary[key] as? String {
                let cleaned = clean(message)
                if !cleaned.isEmpty { return cleaned }
            }
            if let entries = dictionary[key] as? [[String: Any]] {
                let messages = entries.compactMap { entry -> String? in
                    guard let message = entry["msg"] as? String else { return nil }
                    let cleaned = clean(message)
                    return cleaned.isEmpty ? nil : cleaned
                }
                if !messages.isEmpty { return messages.joined(separator: "; ") }
            }
        }
        return nil
    }

    static func clean(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
