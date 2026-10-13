import AppKit
import GLKBCiteCore

/// Writes a citation to a pasteboard as plain text plus RTF and HTML
/// flavours, so its italics survive pasting into rich-text editors while
/// plain-text targets receive the bare citation.
enum CitationPasteboard {
    static func write(_ citation: FormattedCitation, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(citation.plainText, forType: .string)
        if let rtf = rtfData(for: citation) { item.setData(rtf, forType: .rtf) }
        item.setString(citation.html, forType: .html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// RTF with the italic runs set in the italic face of the system font
    /// and linked runs carrying their URL.
    static func rtfData(for citation: FormattedCitation) -> Data? {
        let roman = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let italic = NSFontManager.shared.convert(roman, toHaveTrait: .italicFontMask)
        let text = NSMutableAttributedString()
        for run in citation.runs {
            var attributes: [NSAttributedString.Key: Any] = [.font: run.isItalic ? italic : roman]
            if let link = run.link { attributes[.link] = link }
            text.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
