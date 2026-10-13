import Foundation

/// A citation as styled text: a sequence of runs that are either roman or
/// italic, optionally hyperlinked, so the same rendering can be shown in the
/// UI, copied as rich text, or flattened to plain text.
public struct FormattedCitation: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var isItalic: Bool
        /// The destination when the run is a hyperlink, such as the PubMed URL.
        public var link: URL?

        public init(text: String, isItalic: Bool = false, link: URL? = nil) {
            self.text = text
            self.isItalic = isItalic
            self.link = link
        }
    }

    public var runs: [Run]

    /// Adjacent runs with the same styling are merged and empty runs
    /// dropped, so consumers see the minimal sequence.
    public init(runs: [Run]) {
        var merged: [Run] = []
        for run in runs where !run.text.isEmpty {
            if let last = merged.last, last.isItalic == run.isItalic, last.link == run.link {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        self.runs = merged
    }

    /// The citation without styling.
    public var plainText: String { runs.map(\.text).joined() }

    /// The citation with italic runs carrying the `emphasized` inline
    /// presentation intent, which SwiftUI's `Text` renders in italics.
    /// Links are left out: the Cite panel's boxes copy on click.
    public var attributedString: AttributedString {
        runs.reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            if run.isItalic { piece.inlinePresentationIntent = .emphasized }
            result.append(piece)
        }
    }

    /// The citation as an HTML fragment, italic runs wrapped in `<i>` and
    /// linked runs in `<a href>`.
    public var html: String {
        runs.map { run in
            var fragment = Self.escapeHTML(run.text)
            if run.isItalic { fragment = "<i>\(fragment)</i>" }
            if let link = run.link {
                fragment = "<a href=\"\(Self.escapeHTML(link.absoluteString))\">\(fragment)</a>"
            }
            return fragment
        }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
