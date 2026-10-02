import SwiftUI

/// Lucide's "quote" icon (https://lucide.dev, icons/quote.svg), reproduced
/// from the official SVG path so the Cite button shows the real icon rather
/// than a look-alike glyph. Lucide is licensed under the ISC License,
/// Copyright (c) Lucide Icons and Contributors.
///
/// Lucide icons are stroked outlines on a 24-unit grid: this shape carries
/// the geometry (arcs converted to cubic curves) and scales it to the frame
/// it is given; `LucideQuoteIcon` applies the set's standard 2-unit stroke
/// with round caps and joins.
struct LucideQuoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 16, y: 3))
        path.addCurve(to: CGPoint(x: 14, y: 5), control1: CGPoint(x: 14.895, y: 3), control2: CGPoint(x: 14, y: 3.895))
        path.addLine(to: CGPoint(x: 14, y: 11))
        path.addCurve(to: CGPoint(x: 16, y: 13), control1: CGPoint(x: 14, y: 12.105), control2: CGPoint(x: 14.895, y: 13))
        path.addCurve(to: CGPoint(x: 17, y: 14), control1: CGPoint(x: 16.552, y: 13), control2: CGPoint(x: 17, y: 13.448))
        path.addLine(to: CGPoint(x: 17, y: 15))
        path.addCurve(to: CGPoint(x: 15, y: 17), control1: CGPoint(x: 17, y: 16.105), control2: CGPoint(x: 16.105, y: 17))
        path.addCurve(to: CGPoint(x: 14, y: 18), control1: CGPoint(x: 14.448, y: 17), control2: CGPoint(x: 14, y: 17.448))
        path.addLine(to: CGPoint(x: 14, y: 20))
        path.addCurve(to: CGPoint(x: 15, y: 21), control1: CGPoint(x: 14, y: 20.552), control2: CGPoint(x: 14.448, y: 21))
        path.addCurve(to: CGPoint(x: 21, y: 15), control1: CGPoint(x: 18.314, y: 21), control2: CGPoint(x: 21, y: 18.314))
        path.addLine(to: CGPoint(x: 21, y: 5))
        path.addCurve(to: CGPoint(x: 19, y: 3), control1: CGPoint(x: 21, y: 3.895), control2: CGPoint(x: 20.105, y: 3))
        path.closeSubpath()
        path.move(to: CGPoint(x: 5, y: 3))
        path.addCurve(to: CGPoint(x: 3, y: 5), control1: CGPoint(x: 3.895, y: 3), control2: CGPoint(x: 3, y: 3.895))
        path.addLine(to: CGPoint(x: 3, y: 11))
        path.addCurve(to: CGPoint(x: 5, y: 13), control1: CGPoint(x: 3, y: 12.105), control2: CGPoint(x: 3.895, y: 13))
        path.addCurve(to: CGPoint(x: 6, y: 14), control1: CGPoint(x: 5.552, y: 13), control2: CGPoint(x: 6, y: 13.448))
        path.addLine(to: CGPoint(x: 6, y: 15))
        path.addCurve(to: CGPoint(x: 4, y: 17), control1: CGPoint(x: 6, y: 16.105), control2: CGPoint(x: 5.105, y: 17))
        path.addCurve(to: CGPoint(x: 3, y: 18), control1: CGPoint(x: 3.448, y: 17), control2: CGPoint(x: 3, y: 17.448))
        path.addLine(to: CGPoint(x: 3, y: 20))
        path.addCurve(to: CGPoint(x: 4, y: 21), control1: CGPoint(x: 3, y: 20.552), control2: CGPoint(x: 3.448, y: 21))
        path.addCurve(to: CGPoint(x: 10, y: 15), control1: CGPoint(x: 7.314, y: 21), control2: CGPoint(x: 10, y: 18.314))
        path.addLine(to: CGPoint(x: 10, y: 5))
        path.addCurve(to: CGPoint(x: 8, y: 3), control1: CGPoint(x: 10, y: 3.895), control2: CGPoint(x: 9.105, y: 3))
        path.closeSubpath()

        let scale = min(rect.width, rect.height) / 24
        return path.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(
                    translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale
                ))
        )
    }
}

/// The Lucide "quote" icon at a given point size, drawn in the current
/// foreground style with Lucide's proportional 2-of-24 stroke.
struct LucideQuoteIcon: View {
    var size: CGFloat

    var body: some View {
        LucideQuoteShape()
            .stroke(.foreground, style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
