import AppKit
import GLKBCiteCore
import SwiftUI

/// Content of the 460pt "Cite" modal: one box per citation style (click to
/// copy), BibTeX / EndNote exports, and the confirmation toast. Copying keeps
/// the modal open, as in the mockup; ✕, Escape, or the dimmed panel close it.
struct CitePanelView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        ZStack(alignment: .top) {
            if let reference = coordinator.citeReference {
                sheet(for: reference)
            } else {
                Color.clear.frame(width: 460, height: 10)
            }

            if coordinator.citeReference != nil, let message = coordinator.toastMessage {
                ToastView(message: message)
                    .padding(.top, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(3)
            }
        }
        .animation(.easeOut(duration: 0.15), value: coordinator.toastMessage)
    }

    private func sheet(for reference: LiteratureReference) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Text("Cite")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 14, trailing: 0))
                .background(WindowDragHandle())

                CircularCloseButton { coordinator.dismissCite() }
                    .padding(.trailing, 20)
            }

            Divider().overlay(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(CitationFormatter.Style.allCases, id: \.rawValue) { style in
                        Text(style.rawValue)
                            .font(.system(size: 12.5, weight: .bold))
                            .padding(.top, style == CitationFormatter.Style.allCases.first ? 0 : 8)
                            // The visible label matches the mockup; the edition or
                            // variant (e.g. Chicago notes-bibliography) is a tooltip.
                            .help(style.longName)
                            .accessibilityLabel(style.longName)
                        FormatBox(
                            label: "\(style.longName) citation",
                            text: CitationFormatter.citation(for: reference, style: style)
                        ) {
                            copy(CitationFormatter.citation(for: reference, style: style))
                            coordinator.showToast("\(style.rawValue) citation copied to clipboard")
                        }
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
            }
            .frame(maxHeight: 460)

            Divider().overlay(Theme.hairline)

            HStack(spacing: 10) {
                Button("BibTeX") {
                    copy(CitationFormatter.bibtex(for: reference))
                    coordinator.showToast("BibTeX entry copied to clipboard")
                }
                .buttonStyle(OutlineButtonStyle())

                Button("EndNote") {
                    copy(CitationFormatter.ris(for: reference))
                    coordinator.showToast("EndNote (RIS) record copied to clipboard")
                }
                .buttonStyle(OutlineButtonStyle())

                Spacer()
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 18, trailing: 20))
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.windowCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.windowCornerRadius)
                .strokeBorder(Theme.hairline)
        )
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A citation rendering that copies on click and tints on hover.
private struct FormatBox: View {
    /// Accessible name of the control ("APA 7 citation").
    let label: String
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .background(isHovered ? Theme.accentSoft : Theme.insetSurface,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help("Copy this \(label)")
        .accessibilityLabel(label)
        .accessibilityValue(text)
        .accessibilityHint("Copies the citation to the clipboard")
    }
}
