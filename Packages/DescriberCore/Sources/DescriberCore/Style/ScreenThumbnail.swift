import Foundation

/// A rectangle of a screen's thumbnail, in thumbnail points with the origin at the box's top-left.
public struct ThumbnailRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// What a screen's small preview in the sidebar draws (milestone 14): the sheet scaled to fit a box, and each region
/// scaled the same way, in its kind family's colors, back to front.
public struct ScreenThumbnail: Hashable, Sendable {
    public struct Region: Hashable, Sendable {
        public var frame: ThumbnailRect
        public var family: KindFamily
    }

    /// The sheet, centered in the box with the screen's aspect kept.
    public var sheet: ThumbnailRect
    public var sheetRadius: Double
    /// Back to front, as the canvas draws them.
    public var regions: [Region]

    /// The most regions a thumbnail draws: the topmost ones, since they cover the rest.
    public static let maximumRegions = 300
    /// Regions narrower or shorter than this at the thumbnail's size are left out.
    public static let minimumSize = 0.5

    /// The thumbnail of `screen` fitting a `width` × `height` box. Regions in scrolling content are drawn at scroll
    /// offset zero and clipped to their scrolling parent.
    public static func rects(for screen: Screen, width: Double, height: Double) -> ScreenThumbnail {
        let bounds = screen.canvasBounds
        let scale = bounds.w > 0 && bounds.h > 0 ? min(width / Double(bounds.w), height / Double(bounds.h)) : 0
        let sheetWidth = Double(bounds.w) * scale
        let sheetHeight = Double(bounds.h) * scale
        let originX = (width - sheetWidth) / 2
        let originY = (height - sheetHeight) / 2
        let sheet = ThumbnailRect(x: originX, y: originY, w: sheetWidth, h: sheetHeight)
        let radius = min(PaperShapes.sheetCornerRadius(for: screen) * scale, sheetWidth / 2, sheetHeight / 2)
        guard scale > 0 else {
            return ScreenThumbnail(sheet: sheet, sheetRadius: 0, regions: [])
        }
        let layout = ScrollLayout(screen: screen)
        var regions: [Region] = []
        for region in screen.allRegions {
            guard let visible = layout.visibleFrame(of: region.id) else { continue }
            let w = Double(visible.w) * scale
            let h = Double(visible.h) * scale
            guard w >= minimumSize, h >= minimumSize else { continue }
            let frame = ThumbnailRect(
                x: originX + Double(visible.x - bounds.x) * scale, y: originY + Double(visible.y - bounds.y) * scale,
                w: w, h: h)
            regions.append(Region(frame: frame, family: region.kind.family))
        }
        if regions.count > maximumRegions {
            regions.removeFirst(regions.count - maximumRegions)
        }
        return ScreenThumbnail(sheet: sheet, sheetRadius: radius, regions: regions)
    }

    /// A value that changes when anything a thumbnail draws changes: the screen's kind, viewport and scrolling, and
    /// its regions' frames, kinds and nesting. Titles and descriptions don't count.
    public static func fingerprint(of screen: Screen) -> Int {
        var hasher = Hasher()
        hasher.combine(screen.kind)
        hasher.combine(screen.viewport)
        hasher.combine(screen.scroll)
        func walk(_ regions: [DescriberCore.Region]) {
            hasher.combine(regions.count)
            for region in regions {
                hasher.combine(region.frame)
                hasher.combine(region.kind)
                hasher.combine(region.scroll)
                walk(region.children)
            }
        }
        walk(screen.regions)
        return hasher.finalize()
    }
}
