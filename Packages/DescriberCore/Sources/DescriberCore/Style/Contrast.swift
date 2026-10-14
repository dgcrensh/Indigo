import Foundation

/// WCAG 2 contrast between colors, which the palette's tests hold to.
public enum Contrast {
    /// The contrast ratio of two colors, from 1 to 21. A translucent `foreground` is composited over `background`
    /// first; `background` is taken as opaque.
    public static func ratio(_ foreground: PaperColor, _ background: PaperColor) -> Double {
        let first = luminance(foreground.composited(over: background.withAlpha(1)))
        let second = luminance(background.withAlpha(1))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// The relative luminance of an opaque color.
    public static func luminance(_ color: PaperColor) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}
