import SwiftUI

struct GlyphKey: LayoutValueKey { static let defaultValue = "" }
struct ProbeKey: LayoutValueKey { static let defaultValue = false }

/// Measures using the inherited SwiftUI font, including Dynamic Type.
struct MorphLayout: Layout {
    var alignment: TextMorphConfiguration.Alignment
    var lineSpacing: CGFloat

    struct Arrangement {
        var points: [CGPoint]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for i in subviews.indices {
            subviews[i].place(at: CGPoint(x: bounds.minX + layout.points[i].x,
                                         y: bounds.minY + layout.points[i].y),
                              anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let dimensions = subviews.map { $0.dimensions(in: .unspecified) }
        let limit = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? .infinity
        let height = dimensions.map(\.height).max() ?? 0
        let baseline = dimensions.map { $0[.firstTextBaseline] }.max() ?? 0
        var points = Array(repeating: CGPoint.zero, count: subviews.count)
        var rows: [(Range<Int>, CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, maxWidth: CGFloat = 0, rowStart = 0
        let count = subviews.firstIndex(where: { $0[ProbeKey.self] }) ?? subviews.count
        var i = 0
        func breakLine(at end: Int) {
            rows.append((rowStart..<end, x))
            maxWidth = max(maxWidth, x)
            rowStart = end; x = 0; y += height + max(0, lineSpacing)
        }
        while i < count {
            let glyph = subviews[i][GlyphKey.self]
            if glyph.contains("\n") || glyph == "\r" {
                points[i] = CGPoint(x: x, y: y)
                breakLine(at: i + 1); i += 1; continue
            }
            // Wrap at word boundaries; oversized words fall back to grapheme wrapping.
            let isSpace = glyph.allSatisfy(\.isWhitespace)
            if !isSpace && (i == 0 || subviews[i - 1][GlyphKey.self].allSatisfy(\.isWhitespace)) {
                var end = i, wordWidth: CGFloat = 0
                while end < count && !subviews[end][GlyphKey.self].allSatisfy(\.isWhitespace) {
                    wordWidth += dimensions[end].width; end += 1
                }
                if x > 0 && x + wordWidth > limit + 0.5 { breakLine(at: i) }
            }
            let glyphWidth = dimensions[i].width
            if !isSpace && x > 0 && x + glyphWidth > limit + 0.5 { breakLine(at: i) }
            points[i] = CGPoint(x: x, y: y + baseline - dimensions[i][.firstTextBaseline])
            x += glyphWidth; i += 1
        }
        rows.append((rowStart..<count, x)); maxWidth = max(maxWidth, x)
        let actualWidth = limit.isFinite ? min(ceil(maxWidth), limit) : ceil(maxWidth)
        for (range, rowWidth) in rows {
            let offset: CGFloat = switch alignment {
            case .leading: 0
            case .center: max(0, actualWidth - rowWidth) / 2
            case .trailing: max(0, actualWidth - rowWidth)
            }
            for index in range { points[index].x += offset }
        }
        return Arrangement(points: points, size: CGSize(width: actualWidth, height: y + height))
    }
}
