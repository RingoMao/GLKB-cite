import GLKBCiteCore
import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch coordinator.phase {
                case .idle:
                    idleView
                case .loading:
                    loadingView
                case .completed:
                    completedView
                case .failed:
                    errorView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if coordinator.phase == .completed {
                Divider()
                resultToolbar
            }
        }
        .frame(minWidth: 500, idealWidth: 620, minHeight: 420, idealHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.book.closed.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("GLKB Citations")
                    .font(.headline)
                if let source = coordinator.selection?.sourceApplicationName {
                    Text("Selection from \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if coordinator.result?.isCached == true {
                Label("Cached · no API call", systemImage: "bolt.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var idleView: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.cursor")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Select scientific text to begin")
                .font(.headline)
            Text("Press Option-Command-G to find citations.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(coordinator.progressStep)
                .font(.headline)
            if let content = coordinator.progressContent, !content.isEmpty {
                Text(content)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            selectionDisclosure
            Button("Cancel") {
                coordinator.cancelQuery()
            }
        }
        .padding(30)
    }

    private var completedView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let answer = coordinator.result?.answer,
                   !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Retrieval summary", systemImage: "quote.bubble")
                        .font(.headline)
                        MarkdownText(answer)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Text("References")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(coordinator.result?.references.count ?? 0)")
                        .foregroundStyle(.secondary)
                }

                if let references = coordinator.result?.references, references.isEmpty {
                    Text("No supporting PubMed references were found for this sentence. This is a normal result for text without a citable scientific claim.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(coordinator.result?.references ?? []) { reference in
                        LiteratureReferenceCard(
                            reference: reference,
                            includeEvidence: settings.includeEvidence
                        ) {
                            coordinator.openReference(reference)
                        }
                    }
                }

                selectionDisclosure

                Label(
                    "Verify each source before citation, publication, or clinical use.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(18)
        }
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("GLKB Cite could not complete the request")
                .font(.headline)
            Text(coordinator.errorMessage ?? "An unknown error occurred.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 430)
            HStack {
                if coordinator.errorMessage?.localizedCaseInsensitiveContains("key") == true {
                    Button("Open Settings") {
                        coordinator.showSettings()
                    }
                }
                if coordinator.errorMessage?.localizedCaseInsensitiveContains("Accessibility") == true {
                    Button("Open Accessibility Settings") {
                        coordinator.openAccessibilitySettings()
                    }
                }
                if coordinator.canRetryLastQuery {
                    Button("Retry") {
                        coordinator.retryLastQuery()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(30)
    }

    private var resultToolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Copy Rich Report") { coordinator.copyRichReport() }
                Button("Copy Plain Text") { coordinator.copyPlainReport() }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Spacer()

            Button {
                coordinator.openAllReferencesInPubMed()
            } label: {
                Label("Open in PubMed", systemImage: "safari")
            }
            .disabled(coordinator.result?.references.isEmpty != false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var selectionDisclosure: some View {
        if let selectedText = coordinator.selection?.selectedText, !selectedText.isEmpty {
            DisclosureGroup("Selected passage") {
                Text(selectedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .font(.callout)
        }
    }
}

private struct MarkdownText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: value) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LiteratureReferenceCard: View {
    let reference: LiteratureReference
    let includeEvidence: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(reference.title)
                .font(.headline)
                .textSelection(.enabled)

            if !metadata.isEmpty {
                Text(metadata)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let reason = reference.relevanceReason, !reason.isEmpty {
                Text(reason)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
            }

            Button(action: open) {
                HStack(spacing: 5) {
                    Text("PMID \(reference.pmid)")
                    Image(systemName: "arrow.up.right.square")
                }
            }
            .buttonStyle(.link)

            if includeEvidence,
               let evidence = reference.evidence.first?.quote,
               !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                    Text(evidence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var metadata: String {
        let authors: String
        if reference.authors.count <= 3 {
            authors = reference.authors.joined(separator: ", ")
        } else {
            authors = reference.authors.prefix(3).joined(separator: ", ") + ", et al."
        }
        let citationCount = reference.citationCount.map { "\($0) citations" }
        return [authors, reference.journal, reference.date, citationCount]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
