import AppKit
import CoreText

/// Region titles laid out once and kept between draws, so panning never lays out text again and zooming only
/// re-truncates titles that don't fit. One per canvas; the renderer draws through it.
final class TitleCache {
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// Truncated lines kept before the cache starts over, since every zoom level adds widths.
    private static let truncatedLimit = 4000

    private struct TruncatedKey: Hashable {
        var title: String
        var width: Int
    }

    private var lines: [String: (line: CTLine, width: CGFloat)] = [:]
    private var truncatedLines: [TruncatedKey: CTLine] = [:]
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: TitleCache.font,
        // The text takes the context's fill color, so one cached line works in light and dark appearances.
        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    private lazy var ellipsis = CTLineCreateWithAttributedString(
        NSAttributedString(string: "…", attributes: attributes))

    /// The height of one line of title text.
    let lineHeight = ceil(TitleCache.font.ascender - TitleCache.font.descender + TitleCache.font.leading)
    let ascent = TitleCache.font.ascender

    /// `title` laid out on one line, truncated at the end to fit `width`, or nil when not even the ellipsis fits.
    func line(for title: String, fitting width: CGFloat) -> CTLine? {
        let full = fullLine(for: title)
        if full.width <= width {
            return full.line
        }
        let key = TruncatedKey(title: title, width: Int(width.rounded(.down)))
        if let line = truncatedLines[key] {
            return line
        }
        guard let line = CTLineCreateTruncatedLine(full.line, Double(key.width), .end, ellipsis) else { return nil }
        if truncatedLines.count >= Self.truncatedLimit {
            truncatedLines.removeAll(keepingCapacity: true)
        }
        truncatedLines[key] = line
        return line
    }

    private func fullLine(for title: String) -> (line: CTLine, width: CGFloat) {
        if let cached = lines[title] {
            return cached
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attributes))
        let entry = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        lines[title] = entry
        return entry
    }
}
