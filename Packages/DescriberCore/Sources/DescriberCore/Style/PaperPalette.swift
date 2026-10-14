import Foundation

/// A color of the Paper look, in sRGB with components from 0 to 1.
public struct PaperColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A color from a hex value such as `0x4A4FD1`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    /// The same color at `alpha`.
    public func withAlpha(_ alpha: Double) -> PaperColor {
        PaperColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// The opaque color this one makes drawn over `background`.
    public func composited(over background: PaperColor) -> PaperColor {
        PaperColor(
            red: red * alpha + background.red * (1 - alpha), green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha))
    }
}

/// Which version of the Paper look to use. It follows the Mac's light or dark appearance.
public enum PaperAppearance: CaseIterable, Sendable {
    case light
    /// "Night paper": the same look on warm charcoal.
    case dark
}

/// Every color of the Paper look (milestone 13), for one appearance.
public struct PaperPalette: Hashable, Sendable {
    /// The canvas background around the screen.
    public var desk: PaperColor
    public var gridDot: PaperColor
    /// The screen's own area, drawn as a sheet on the desk.
    public var sheet: PaperColor
    public var sheetBorder: PaperColor
    public var sheetShadow: PaperColor
    /// Panel and window backgrounds.
    public var chrome: PaperColor
    /// Cards: the details card, the tool pill, the toast, the settings banner.
    public var card: PaperColor
    /// Field backgrounds.
    public var well: PaperColor
    public var ink: PaperColor
    public var secondaryInk: PaperColor
    public var accent: PaperColor
    /// Text on an accent fill, such as the active tool's button.
    public var onAccent: PaperColor
    /// The tint over parts of regions outside the screen's bounds.
    public var outside: PaperColor
    /// Each kind family's fill, border and text colors.
    public var families: [KindFamily: KindFamilyColors]

    public static let light = PaperPalette(
        desk: PaperColor(hex: 0xEAE5DB),
        gridDot: PaperColor(hex: 0xD3CBBD),
        sheet: PaperColor(hex: 0xFFFDF9),
        sheetBorder: PaperColor(hex: 0xDDD5C8),
        sheetShadow: PaperColor(hex: 0x3A332C, alpha: 0.14),
        chrome: PaperColor(hex: 0xF4F1EA),
        card: PaperColor(hex: 0xFFFFFF),
        well: PaperColor(hex: 0xF4F1EA),
        ink: PaperColor(hex: 0x2A2622),
        secondaryInk: PaperColor(hex: 0x6E655B),
        accent: PaperColor(hex: 0x4A4FD1),
        onAccent: PaperColor(hex: 0xFFFFFF),
        outside: PaperColor(hex: 0xD9534F, alpha: 0.2),
        families: [
            .neutral: KindFamilyColors(fill: 0xF4F1EA, border: 0xC7BEAE, text: 0x3A332C),
            .structure: KindFamilyColors(fill: 0xEFECF9, border: 0xB9AEE6, text: 0x3D3470),
            .content: KindFamilyColors(fill: 0xDCEAF7, border: 0x8DB4DA, text: 0x2E4A66),
            .action: KindFamilyColors(fill: 0xFBE1CC, border: 0xE3A97A, text: 0x6B3A12),
            .input: KindFamilyColors(fill: 0xDDF1E8, border: 0x8CC9AE, text: 0x22543F),
        ])

    public static let dark = PaperPalette(
        desk: PaperColor(hex: 0x1F1C19),
        gridDot: PaperColor(hex: 0x3A352F),
        sheet: PaperColor(hex: 0x2B2723),
        sheetBorder: PaperColor(hex: 0x3F3A33),
        sheetShadow: PaperColor(hex: 0x000000, alpha: 0.45),
        chrome: PaperColor(hex: 0x26231F),
        card: PaperColor(hex: 0x2F2B26),
        well: PaperColor(hex: 0x24211D),
        ink: PaperColor(hex: 0xEDE7DC),
        secondaryInk: PaperColor(hex: 0xA39A8E),
        accent: PaperColor(hex: 0x8C90F0),
        onAccent: PaperColor(hex: 0x1F1C19),
        outside: PaperColor(hex: 0xD9534F, alpha: 0.2),
        families: [
            .neutral: KindFamilyColors(fill: 0x34302B, border: 0x5A5248, text: 0xE8E1D6),
            .structure: KindFamilyColors(fill: 0x2F2B47, border: 0x6A5FB0, text: 0xD9D3FA),
            .content: KindFamilyColors(fill: 0x23344A, border: 0x4F7AA6, text: 0xCFE2F7),
            .action: KindFamilyColors(fill: 0x45301F, border: 0xB07A4C, text: 0xF7D9BF),
            .input: KindFamilyColors(fill: 0x1F3A30, border: 0x4E9A7A, text: 0xCDEEDF),
        ])

    public static func palette(for appearance: PaperAppearance) -> PaperPalette {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }

    /// The fill, border and text colors of `family`.
    public func colors(for family: KindFamily) -> KindFamilyColors {
        families[family] ?? KindFamilyColors(fill: 0xFFFFFF, border: 0x000000, text: 0x000000)
    }

    /// The fill, border and text colors of regions of `kind`.
    public func colors(for kind: RegionKind) -> KindFamilyColors {
        colors(for: kind.family)
    }
}

/// The colors a kind family's regions and chips are drawn in.
public struct KindFamilyColors: Hashable, Sendable {
    public var fill: PaperColor
    public var border: PaperColor
    /// Titles on the fill, and descriptions at 80%.
    public var text: PaperColor

    public init(fill: PaperColor, border: PaperColor, text: PaperColor) {
        self.fill = fill
        self.border = border
        self.text = text
    }

    init(fill: UInt32, border: UInt32, text: UInt32) {
        self.init(fill: PaperColor(hex: fill), border: PaperColor(hex: border), text: PaperColor(hex: text))
    }
}
