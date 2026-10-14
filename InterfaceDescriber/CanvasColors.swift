import AppKit

/// The canvas colors, resolved for one appearance so layers can use them as `CGColor`s.
struct CanvasColors {
    var boundsFill: CGColor
    var boundsBorder: CGColor
    var grid: CGColor
    var regionFill: CGColor
    var regionBorder: CGColor
    var outside: CGColor
    var title: CGColor
    var emptyText: CGColor

    init(appearance: NSAppearance) {
        var colors: [CGColor] = []
        appearance.performAsCurrentDrawingAppearance {
            colors = [
                NSColor.textBackgroundColor,
                NSColor.secondaryLabelColor,
                NSColor.separatorColor.withAlphaComponent(0.4),
                NSColor.controlAccentColor.withAlphaComponent(0.06),
                NSColor.secondaryLabelColor,
                NSColor.systemRed.withAlphaComponent(0.2),
                NSColor.labelColor,
                NSColor.secondaryLabelColor,
            ].map(\.cgColor)
        }
        boundsFill = colors[0]
        boundsBorder = colors[1]
        grid = colors[2]
        regionFill = colors[3]
        regionBorder = colors[4]
        outside = colors[5]
        title = colors[6]
        emptyText = colors[7]
    }
}
