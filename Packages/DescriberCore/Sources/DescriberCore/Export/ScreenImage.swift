import Foundation

/// What a screen's PNG export covers and what its files are called (spec Section 11).
public enum ScreenImage {
    /// The scales a screen can be exported at.
    public static let scales = [1, 2]

    /// The area of the screen, in screen points, that its image shows: the canvas bounds, widened to take in every
    /// part of a region drawn outside them. Regions are where the scroll `offsets` draw them, and only their parts
    /// inside their clip count, so content scrolled out of view doesn't widen the image.
    public static func extent(of screen: Screen, offsets: [RegionID: ScrollOffset] = [:]) -> Frame {
        let layout = ScrollLayout(screen: screen, offsets: offsets)
        var extent = screen.canvasBounds
        for region in screen.allRegions {
            if let visible = layout.visibleFrame(of: region.id) {
                extent = extent.union(visible)
            }
        }
        return extent
    }

    /// Each screen's PNG file name: the slug its screen file uses, with `@2x` (or `@3x`, and so on) above 1×.
    public static func fileNames(for project: Project, scale: Int) -> [ScreenID: String] {
        let suffix = scale > 1 ? "@\(scale)x" : ""
        let slugs = Slug.unique(project.screens.map(\.name))
        var names: [ScreenID: String] = [:]
        for (screen, slug) in zip(project.screens, slugs) {
            names[screen.id] = "\(slug)\(suffix).png"
        }
        return names
    }
}

extension Frame {
    /// The smallest frame containing both frames.
    public func union(_ other: Frame) -> Frame {
        let minX = Swift.min(x, other.x)
        let minY = Swift.min(y, other.y)
        return Frame(
            x: minX, y: minY, w: Swift.max(maxX, other.maxX) - minX, h: Swift.max(maxY, other.maxY) - minY)
    }
}
