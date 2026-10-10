import GLKBCiteCore
import SwiftUI

/// The floating results panel. Layout and states follow the product mockup:
/// header (mark, title, state subtitle, close), grouped reference cards,
/// copy actions with a disclaimer, and loading / empty / error states.
struct ResultPanelView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PanelHeader(subtitle: subtitle) {
                    coordinator.hideResultPanel()
                }
                Divider().overlay(Theme.hairline)

                switch coordinator.phase {
                case .idle, .loading:
                    loadingView
                case .completed:
                    completedView
                case .failed:
                    errorView
                }
            }

            // While the Cite modal (a separate 460pt panel) is up, dim this
            // panel like the mockup's overlay; a tap on the dim closes it.
            if coordinator.citeReference != nil {
                Color.black.opacity(0.28)
                    .onTapGesture { coordinator.dismissCite() }
                    .zIndex(1)
            } else if let message = coordinator.toastMessage {
                ToastView(message: message)
                    .padding(.top, 54)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(3)
            }
        }
        .frame(width: 380)
        .frame(
            minHeight: AppCoordinator.minimumResultPanelHeight,
            maxHeight: coordinator.resultPanelMaxHeight,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.windowCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.windowCornerRadius)
                .strokeBorder(Theme.hairline)
        )
        .animation(.easeOut(duration: 0.15), value: coordinator.toastMessage)
        .animation(.easeOut(duration: 0.15), value: coordinator.citeReference?.id)
    }

    /// State subtitles are the mockup's exact strings.
    private var subtitle: String {
        switch coordinator.phase {
        case .idle, .loading:
            return "Searching…"
        case .completed:
            return coordinator.result?.references.isEmpty == false
                ? "Literature evidence for the text you select"
                : "No structured references found"
        case .failed:
            return isKeyError ? "Authorization required" : "Request declined"
        }
    }

    private var isKeyError: Bool {
        coordinator.failureKind == .invalidKey || coordinator.failureKind == .missingKey
    }

    private var isAccessibilityError: Bool {
        coordinator.failureKind == .accessibility
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Searching literature evidence…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 44)
    }

    @ViewBuilder
    private var completedView: some View {
        if let result = coordinator.result, !result.references.isEmpty {
            resultsView(result)
        } else {
            StatusView(
                icon: .neutral("info.circle"),
                headline: "No citation result is available yet",
                body: "The service returned no structured PubMed references for this request. Try selecting a more specific sentence.",
                button: ("Retry", .secondary, coordinator.canRetryLastQuery)
            ) {
                coordinator.retryLastQuery()
            }
        }
    }

    private func resultsView(_ result: LiteratureResult) -> some View {
        let groups = ReferenceGroup.make(from: result.references)
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(groups) { group in
                        GroupLabel(group.title)
                        ForEach(group.entries, id: \.reference.id) { entry in
                            ReferenceCard(
                                index: entry.index,
                                reference: entry.reference,
                                includeEvidence: settings.includeEvidence,
                                open: { coordinator.openReference(entry.reference) },
                                cite: { coordinator.presentCite(entry.reference) }
                            )
                        }
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12))
            }

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Button("Copy Plain Text") {
                        coordinator.copyPlainReport()
                        coordinator.showToast("Plain-text report copied to clipboard")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Button("Copy Rich Report") {
                        coordinator.copyRichReport()
                        coordinator.showToast("Rich report copied to clipboard")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
                Text("Generated from GLKB/PubMed evidence. Verify each source before citing.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
        }
    }

    private var errorView: some View {
        StatusView(
            icon: .warning,
            headline: errorHeadline,
            body: errorBody,
            button: primaryErrorAction
        ) {
            if isKeyError {
                coordinator.showSettings()
            } else if isAccessibilityError {
                coordinator.openAccessibilitySettings()
            } else {
                coordinator.retryLastQuery()
            }
        }
    }

    private var errorHeadline: String {
        switch coordinator.failureKind {
        case .invalidKey, .missingKey:
            return "GLKB rejected this API key"
        case .rateLimited:
            return "GLKB declined this request"
        case .accessibility:
            return "Accessibility access is required"
        case .invalidSelection:
            return "This selection cannot be searched"
        default:
            return "GLKB Cite could not complete the request"
        }
    }

    private var errorBody: String {
        switch coordinator.failureKind {
        case .invalidKey, .missingKey:
            return "Replace it with an active glkb_ key in Settings."
        case .rateLimited:
            return "Usage or rate limits were reached. Check the account before retrying."
        default:
            return coordinator.errorMessage ?? "An unknown error occurred."
        }
    }

    private var primaryErrorAction: (String, StatusView.ButtonKind, Bool)? {
        if isKeyError { return ("Open Settings", .primary, true) }
        if isAccessibilityError { return ("Open Accessibility Settings", .primary, true) }
        if coordinator.canRetryLastQuery { return ("Retry", .secondary, true) }
        return nil
    }

}

// MARK: - Grouping

/// The mockup groups references into "Direct evidence" and "Indirect
/// context". GLKB's `why` field is the closest signal the API offers ("Direct
/// evidence for …" vs. contextual wording); when it says nothing either way,
/// a reference with an evidence excerpt counts as direct. Numbering runs
/// continuously across both groups.
private struct ReferenceGroup: Identifiable {
    struct Entry {
        let index: Int
        let reference: LiteratureReference
    }

    let title: String
    let entries: [Entry]
    var id: String { title }

    private static func isDirect(_ reference: LiteratureReference) -> Bool {
        let reason = (reference.relevanceReason ?? "").lowercased()
        if reason.contains("indirect") || reason.contains("context") || reason.contains("background") {
            return false
        }
        if reason.contains("direct") || reason.contains("support") { return true }
        return reference.evidence.contains {
            !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func make(from references: [LiteratureReference]) -> [ReferenceGroup] {
        var direct: [Entry] = []
        var indirect: [Entry] = []
        for (offset, reference) in references.enumerated() {
            let entry = Entry(index: offset + 1, reference: reference)
            if isDirect(reference) { direct.append(entry) } else { indirect.append(entry) }
        }
        var groups: [ReferenceGroup] = []
        if !direct.isEmpty { groups.append(ReferenceGroup(title: "Direct evidence", entries: direct)) }
        if !indirect.isEmpty { groups.append(ReferenceGroup(title: "Indirect context", entries: indirect)) }
        return groups
    }
}

// MARK: - Header

private struct PanelHeader: View {
    let subtitle: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            // Everything except the close button is a drag region, so the
            // header works like a normal window's title bar.
            HStack(spacing: 9) {
                GLKBMark()
                    .fill(Theme.accent)
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("GLKB Citations")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 0))
            .background(WindowDragHandle())

            CircularCloseButton(action: close)
                .padding(.trailing, 14)
        }
    }
}

private struct GroupLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
            .padding(.top, 6)
    }
}

// MARK: - Reference card

private struct ReferenceCard: View {
    let index: Int
    let reference: LiteratureReference
    let includeEvidence: Bool
    let open: () -> Void
    let cite: () -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isHovered = false
    @State private var citeHovered = false
    @State private var quoteExpanded = false
    /// Full Keyboard Access lands on the Cite button; it must be visible then.
    @FocusState private var citeFocused: Bool

    private var citeRevealed: Bool { isHovered || citeFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // The number chip is part of the title's text run (like the
                // mockup's inline <span>), so wrapped lines return to the
                // card's left edge instead of hanging under the first line.
                (numberChip + Text("  ") + Text(reference.title).font(.system(size: 12.5, weight: .bold)))
                    .foregroundStyle(.primary, Theme.insetSurface)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !metadata.isEmpty {
                    metadataLine
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if includeEvidence, let quote = evidenceQuotes.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\u{201C}…\(quote)\u{201D}")
                        .lineLimit(quoteExpanded ? nil : 2)

                    // Expanding also reveals the other excerpts GLKB
                    // returned for this reference; collapsed keeps
                    // showing only the first one, clamped, as before.
                    if quoteExpanded {
                        ForEach(evidenceQuotes.indices.dropFirst(), id: \.self) { index in
                            Text("\u{201C}…\(evidenceQuotes[index])\u{201D}")
                        }
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep the last line clear of the disclosure button.
                .padding(.trailing, 20)
                .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
                .background(Theme.insetSurface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    QuoteDisclosureButton(isExpanded: $quoteExpanded)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 2))
                }
            }

            HStack(spacing: 8) {
                Button(action: open) {
                    Text(footMeta)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Open PMID \(reference.pmid) in PubMed")
                .accessibilityLabel(footMeta)
                .accessibilityHint("Opens the article on PubMed")

                Spacer()

                Button(action: cite) {
                    HStack(spacing: 4) {
                        LucideQuoteIcon(size: 12)
                        Text("Cite")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(citeHovered ? Color.white : Theme.accentDark)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(citeHovered ? Theme.accentDeep : Theme.citeSurface, in: Capsule())
                    .contentShape(Capsule())
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { citeHovered = hovering }
                    }
                }
                .buttonStyle(.plain)
                .focused($citeFocused)
                .help("Copy a formatted citation")
                .accessibilityLabel("Cite")
                .accessibilityHint("Shows citation formats to copy")
                .opacity(citeRevealed ? 1 : 0)
                .offset(x: citeRevealed ? 0 : 3)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 10, trailing: 12))
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.hairline)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        // Hiding the panel delivers no hover-exit event, so the pointer that
        // was over this card would leave it highlighted until the next show.
        .onReceive(coordinator.$isResultPanelVisible) { visible in
            guard !visible else { return }
            isHovered = false
            citeHovered = false
        }
    }

    /// A rounded grey square with the reference number, drawn from the SF
    /// Symbols "N.square.fill" family in palette mode so it sits inline with
    /// the title text: layer 1 (the numeral) takes the secondary text colour,
    /// layer 2 (the square) the panel's inset surface colour.
    private var numberChip: Text {
        guard (0...50).contains(index) else {
            return Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
        }
        return Text(Image(systemName: "\(index).square.fill").symbolRenderingMode(.palette))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.secondary)
    }

    /// Every evidence excerpt of the reference, trimmed, empty ones dropped.
    /// The first is shown collapsed; the rest appear when the quote expands.
    private var evidenceQuotes: [String] {
        reference.evidence
            .map { $0.quote.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// "Authors · Year", authors abbreviated to two plus "et al."
    private var authorsAndYear: String {
        let authors: String
        if reference.authors.count <= 2 {
            authors = reference.authors.joined(separator: ", ")
        } else {
            authors = reference.authors.prefix(2).joined(separator: ", ") + ", et al."
        }
        return [authors, reference.date ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var journalName: String {
        (reference.journal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Authors · Year · Journal"
    private var metadata: String {
        [authorsAndYear, journalName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The metadata line keeps the journal name whole. Everything sits on
    /// one line when it fits; otherwise the journal moves to its own line
    /// instead of breaking at an arbitrary space, and only a journal name
    /// wider than the card wraps within itself. Separators appear only
    /// between items on the same line, never after the last one.
    @ViewBuilder
    private var metadataLine: some View {
        if authorsAndYear.isEmpty || journalName.isEmpty {
            Text(metadata)
        } else {
            ViewThatFits(in: .horizontal) {
                Text(metadata)
                VStack(alignment: .leading, spacing: 0) {
                    Text(authorsAndYear)
                    Text(journalName)
                }
            }
        }
    }

    /// "PMID: 38291045 · 87 Citations", as in the mockup.
    private var footMeta: String {
        var parts = ["PMID: \(reference.pmid)"]
        if let count = reference.citationCount {
            parts.append("\(count) Citations")
        }
        return parts.joined(separator: " · ")
    }
}

/// The quote box's expand/collapse control. The chevron sits in a 24-point
/// rounded hit area with a hover highlight, so it reads as a button and is
/// easy to hit inside the floating panel, where a missed click would start
/// a window drag instead.
private struct QuoteDisclosureButton: View {
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovered ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 24, height: 22)
                .background(.quaternary.opacity(isHovered ? 1 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(isExpanded ? "Show less" : "Show the full excerpt")
        .accessibilityLabel(isExpanded ? "Collapse quote" : "Expand quote")
    }
}

// MARK: - Status (empty / error / idle)

private struct StatusView: View {
    enum IconKind {
        case warning
        case neutral(String)
    }

    enum ButtonKind {
        case primary
        case secondary
    }

    let icon: IconKind
    let headline: String
    let body_: String
    let button: (title: String, kind: ButtonKind, enabled: Bool)?
    let action: () -> Void

    init(
        icon: IconKind,
        headline: String,
        body: String,
        button: (String, ButtonKind, Bool)? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.icon = icon
        self.headline = headline
        self.body_ = body
        self.button = button
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            iconView
            Text(headline)
                .font(.system(size: 12.5, weight: .semibold))
            Text(body_)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .textSelection(.enabled)
            if let button {
                Group {
                    switch button.kind {
                    case .primary:
                        Button(button.title, action: action)
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    case .secondary:
                        Button(button.title, action: action)
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
                .disabled(!button.enabled)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .padding(.bottom, 40)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(width: 30, height: 30)
                .background(Theme.dangerSoft, in: Circle())
        case .neutral(let symbol):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Theme.insetSurface, in: Circle())
        }
    }
}
