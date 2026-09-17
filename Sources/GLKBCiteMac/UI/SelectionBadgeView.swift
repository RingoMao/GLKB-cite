import SwiftUI

/// The floating "find citations" affordance shown beside the cursor after a
/// text selection. Deliberately high-contrast: it appears over arbitrary app
/// content, so it uses a solid brand-blue tile with a white glyph rather than
/// a translucent material that can vanish against busy backgrounds.
struct SelectionBadgeView: View {
    /// Visual size of the tile itself.
    static let tileSize: CGFloat = 40
    /// Transparent margin around the tile so its shadow is not clipped by
    /// the hosting panel, including the enlarged hover state (tile × 1.1 plus
    /// a 12pt glow with a 3pt offset).
    static let margin: CGFloat = 20
    /// Total size of the hosting panel's content.
    static var panelSize: CGFloat { tileSize + margin * 2 }

    let onFindCitations: () -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        Button(action: onFindCitations) {
            GLKBMark()
                .fill(.white)
                .frame(width: 21, height: 21)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(isHovered ? 1 : 0.96),
                            Theme.accentDeep,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                        .padding(-0.5)
                )
                // Scale before the shadows so the glow radius stays constant
                // and predictable relative to the panel margin.
                .scaleEffect(hasAppeared ? (isHovered ? 1.1 : 1) : 0.6)
                .shadow(color: Theme.accent.opacity(isHovered ? 0.55 : 0.40), radius: isHovered ? 12 : 8, y: 3)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                .opacity(hasAppeared ? 1 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Hover tracking is scoped to the same region as the click
                // target, so the badge never signals interactivity over the
                // transparent shadow margin where a click would do nothing.
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Self.panelSize, height: Self.panelSize)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
        .help("Find citations with GLKB Cite")
        .accessibilityLabel("Find citations for selected text")
    }
}
