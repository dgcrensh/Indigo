import AppKit
import DescriberCore

/// The canvas colors, from the Paper palette for one appearance, as `CGColor`s for layers.
struct CanvasColors {
    /// A kind family's region colors.
    struct Family {
        var fill: CGColor
        var border: CGColor
        var title: CGColor
        /// Descriptions shown on the canvas with `D`: the title color at 80%.
        var description: CGColor
    }

    /// Around the screen. The canvas view draws its own; exported images use this.
    var desk: CGColor
    var gridDot: CGColor
    /// The screen's bounds, drawn as a sheet with a border and a shadow.
    var sheet: CGColor
    var sheetBorder: CGColor
    var sheetShadow: CGColor
    /// The dashed viewport line of a scrolling screen.
    var viewportLine: CGColor
    var outside: CGColor
    var emptyText: CGColor
    /// Selected regions' borders, handle rings, and the outlines of a region being drawn and the marquee.
    var accent: CGColor
    var handleFill: CGColor
    /// Under the region being drawn and the marquee.
    var accentWash: CGColor
    /// The link indicator on regions with links.
    var link: CGColor
    /// The scroll indicators inside scrolling regions and the dashed outline of a selected one's content.
    var scrollIndicator: CGColor
    private var families: [KindFamily: Family]

    init(appearance: NSAppearance) {
        self.init(palette: .palette(for: appearance))
    }

    init(palette: PaperPalette) {
        desk = palette.desk.cgColor
        gridDot = palette.gridDot.cgColor
        sheet = palette.sheet.cgColor
        sheetBorder = palette.sheetBorder.cgColor
        sheetShadow = palette.sheetShadow.cgColor
        viewportLine = palette.accent.withAlpha(0.6).cgColor
        outside = palette.outside.cgColor
        emptyText = palette.secondaryInk.cgColor
        accent = palette.accent.cgColor
        handleFill = palette.card.cgColor
        accentWash = palette.accent.withAlpha(0.08).cgColor
        link = palette.accent.cgColor
        scrollIndicator = palette.accent.withAlpha(0.5).cgColor
        var families: [KindFamily: Family] = [:]
        for family in KindFamily.allCases {
            let colors = palette.colors(for: family)
            families[family] = Family(
                fill: colors.fill.cgColor, border: colors.border.cgColor, title: colors.text.cgColor,
                description: colors.text.withAlpha(0.8).cgColor)
        }
        self.families = families
    }

    /// The colors regions of `kind` are drawn in.
    func family(of kind: RegionKind) -> Family {
        families[kind.family] ?? families[.neutral]!
    }
}
