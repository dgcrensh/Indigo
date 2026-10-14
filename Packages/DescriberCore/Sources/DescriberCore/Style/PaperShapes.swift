import Foundation

/// The corner radii and shadow of the Paper look, in screen points. They scale with zoom like everything else.
public enum PaperShapes {
    /// A region's corner radius when it is big enough for it.
    public static let regionCornerRadius = 6.0
    /// The sheet's shadow: its blur radius and how far it is offset downwards.
    public static let shadowRadius = 12
    public static let shadowOffset = 4
    /// How far past the sheet its shadow reaches, on every side.
    public static var shadowMargin: Int { shadowRadius + shadowOffset }

    /// The corner radius of a `width` × `height` region: 6 pt, but at most a quarter of its shorter side, so small
    /// regions don't turn into pills.
    public static func regionCornerRadius(width: Double, height: Double) -> Double {
        max(min(regionCornerRadius, min(width, height) / 4), 0)
    }

    /// The corner radius of a screen's sheet: an overlay's soft corners, a phone's or a tablet's rounded corners, and
    /// square for every other viewport.
    public static func sheetCornerRadius(for screen: Screen) -> Double {
        if screen.kind != .screen {
            return 12
        }
        switch screen.viewport.preset {
        case "iphone-se", "iphone-15", "iphone-15-pro-max": return 55
        case "ipad", "ipad-pro-13": return 18
        default: return 0
        }
    }
}
