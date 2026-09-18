import AppKit
import SwiftUI

/// Design tokens shared by every GLKB Cite surface.
///
/// Light values mirror the product mockups; dark values are hand-tuned
/// equivalents so each role keeps its contrast relationship in both
/// appearances.
enum Theme {
    // MARK: Brand

    /// Primary brand blue.
    static let accent = Color(red: 0x33 / 255, green: 0x77 / 255, blue: 0xFB / 255)

    /// Darker companion to `accent` for gradient bottoms and pressed states.
    static let accentDeep = Color(red: 0x1F / 255, green: 0x5C / 255, blue: 0xE0 / 255)

    /// Text/icon colour on `accentSoft` containers (mockup `--accent-dark`).
    static let accentDark = dynamic(light: NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1),
                                    dark: NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1))

    /// Tinted container behind primary-colored chips and buttons.
    static let accentSoft = dynamic(light: NSColor(srgbRed: 0.941, green: 0.968, blue: 1.0, alpha: 1),
                                    dark: NSColor(srgbRed: 0.13, green: 0.20, blue: 0.34, alpha: 1))

    /// Amber pair used for citation-count/quantity signals.
    static let amber = dynamic(light: NSColor(srgbRed: 0.541, green: 0.353, blue: 0.110, alpha: 1),
                               dark: NSColor(srgbRed: 0.941, green: 0.753, blue: 0.427, alpha: 1))
    static let amberSoft = dynamic(light: NSColor(srgbRed: 0.965, green: 0.925, blue: 0.859, alpha: 1),
                                   dark: NSColor(srgbRed: 0.28, green: 0.22, blue: 0.11, alpha: 1))

    /// Error pair.
    static let danger = dynamic(light: NSColor(srgbRed: 0.549, green: 0.184, blue: 0.094, alpha: 1),
                                dark: NSColor(srgbRed: 0.976, green: 0.624, blue: 0.529, alpha: 1))
    static let dangerSoft = dynamic(light: NSColor(srgbRed: 0.969, green: 0.906, blue: 0.886, alpha: 1),
                                    dark: NSColor(srgbRed: 0.33, green: 0.15, blue: 0.10, alpha: 1))

    /// Success pair.
    static let success = dynamic(light: NSColor(srgbRed: 0.122, green: 0.420, blue: 0.259, alpha: 1),
                                 dark: NSColor(srgbRed: 0.545, green: 0.859, blue: 0.686, alpha: 1))
    static let successSoft = dynamic(light: NSColor(srgbRed: 0.863, green: 0.941, blue: 0.890, alpha: 1),
                                     dark: NSColor(srgbRed: 0.10, green: 0.27, blue: 0.17, alpha: 1))

    // MARK: Surfaces

    /// Opaque card surface placed on top of the translucent panel material.
    static let cardSurface = dynamic(light: NSColor(srgbRed: 0.992, green: 0.992, blue: 1.0, alpha: 1),
                                     dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1))

    /// Slightly recessed surface (quote boxes, number chips, inputs).
    static let insetSurface = dynamic(light: NSColor(srgbRed: 0.957, green: 0.957, blue: 0.961, alpha: 1),
                                      dark: NSColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1))

    /// Hairline stroke used for card and section borders.
    static let hairline = dynamic(light: NSColor(srgbRed: 0.114, green: 0.161, blue: 0.329, alpha: 0.10),
                                  dark: NSColor(white: 1, alpha: 0.12))

    // MARK: Metrics

    static let windowCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 9

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// The GLKB logotype mark, traced from the brand SVG (240×240 viewbox).
struct GLKBMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 240
        let dx = rect.midX - 120 * s
        let dy = rect.midY - 120 * s
        var path = Path()

        // Outer "C" bracket.
        path.move(to: CGPoint(x: 194.38, y: 29.6))
        path.addLine(to: CGPoint(x: 49.62, y: 29.6))
        path.addQuadCurve(to: CGPoint(x: 45.62, y: 33.6), control: CGPoint(x: 46.6, y: 30.6))
        path.addLine(to: CGPoint(x: 45.62, y: 206.4))
        path.addQuadCurve(to: CGPoint(x: 49.62, y: 210.4), control: CGPoint(x: 46.6, y: 209.4))
        path.addLine(to: CGPoint(x: 194.38, y: 210.4))
        path.addLine(to: CGPoint(x: 194.38, y: 182.28))
        path.addLine(to: CGPoint(x: 71.66, y: 182.28))
        path.addLine(to: CGPoint(x: 71.66, y: 57.72))
        path.addLine(to: CGPoint(x: 194.38, y: 57.72))
        path.closeSubpath()

        // Inner "+"-like glyph.
        path.move(to: CGPoint(x: 120, y: 159.78))
        path.addLine(to: CGPoint(x: 142, y: 159.78))
        path.addLine(to: CGPoint(x: 142, y: 131.15))
        path.addLine(to: CGPoint(x: 187, y: 131.15))
        path.addLine(to: CGPoint(x: 187, y: 108.66))
        path.addLine(to: CGPoint(x: 120, y: 108.66))
        path.closeSubpath()

        return path.applying(
            CGAffineTransform(scaleX: s, y: s)
                .concatenating(CGAffineTransform(translationX: dx, y: dy))
        )
    }
}

// MARK: - Buttons

/// Filled brand-blue button (mockup `.btn.primary`).
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 6 : 8)
            .foregroundStyle(.white)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Bordered neutral button (mockup `.btn.secondary`).
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 6 : 8)
            .foregroundStyle(.primary)
            .background(Theme.cardSurface.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
    }
}

/// Outlined brand-blue button (mockup `.btn.outline`).
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.accent)
            .background(configuration.isPressed ? Theme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent))
    }
}

/// Transient confirmation shown after a copy action.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.success)
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
    }
}

/// Small circular ✕ control used by floating panels.
struct CircularCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}
