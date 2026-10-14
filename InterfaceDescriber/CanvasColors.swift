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
    /// Descriptions shown on the canvas with `D`.
    var description: CGColor
    var emptyText: CGColor
    /// Selected regions' borders, handle borders, and the outlines of a region being drawn and the marquee.
    var selection: CGColor
    var handleFill: CGColor
    var newRegionFill: CGColor
    var marqueeFill: CGColor
    /// The link indicator on regions with links.
    var link: CGColor

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
                NSColor.controlAccentColor,
                NSColor.white,
                NSColor.controlAccentColor.withAlphaComponent(0.12),
                NSColor.controlAccentColor.withAlphaComponent(0.1),
                NSColor.secondaryLabelColor,
                NSColor.linkColor,
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
        selection = colors[8]
        handleFill = colors[9]
        newRegionFill = colors[10]
        marqueeFill = colors[11]
        description = colors[12]
        link = colors[13]
    }
}
