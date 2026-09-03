import Foundation

public protocol LiteratureBackend: Sendable {
    func query(_ query: LiteratureQuery) -> AsyncThrowingStream<LiteratureQueryEvent, Error>
}

public enum LiteratureError: Error, Equatable, Sendable {
    case invalidInput(String)
    case missingCredential
    case invalidEndpoint
    case requestFailed(statusCode: Int, message: String?)
    case malformedResponse(String)
    case transport(String)
    case cancelled
}

extension LiteratureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .missingCredential:
            "Enter a GLKB API key in Settings before searching."
        case .invalidEndpoint:
            "The literature service endpoint is invalid."
        case .requestFailed(let statusCode, let message):
            message.map { "The literature service returned HTTP \(statusCode): \($0)" }
                ?? "The literature service returned HTTP \(statusCode)."
        case .malformedResponse(let message):
            "The literature service returned an unexpected response: \(message)"
        case .transport(let message):
            "The literature request failed: \(message)"
        case .cancelled:
            "The literature request was cancelled."
        }
    }
}
