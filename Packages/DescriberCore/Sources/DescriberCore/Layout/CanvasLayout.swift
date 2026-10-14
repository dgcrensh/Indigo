import Foundation

// On Apple platforms CGRect's geometry lives in CoreGraphics; on Linux, Foundation has it all.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

extension Screen {
    /// The viewport as a frame at the screen's origin.
    public var viewportFrame: Frame {
        Frame(x: 0, y: 0, w: viewport.width, h: viewport.height)
    }

    /// What the canvas draws as the screen: the content area when the screen scrolls, otherwise the viewport.
    /// Parts of regions outside it are marked (spec Section 4).
    public var canvasBounds: Frame {
        guard let scroll else { return viewportFrame }
        return Frame(x: 0, y: 0, w: scroll.contentWidth, h: scroll.contentHeight)
    }
}

extension Frame {
    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// Whether the two frames share some area. Frames that only touch along an edge don't.
    public func intersects(_ other: Frame) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    /// Up to four non-overlapping frames covering the part of this frame outside `bounds`: a band above, a band
    /// below, and the parts left and right of `bounds` between them. Empty when `bounds` contains this frame.
    public func parts(outside bounds: Frame) -> [Frame] {
        guard intersects(bounds) else { return w > 0 && h > 0 ? [self] : [] }
        var parts: [Frame] = []
        if y < bounds.y {
            parts.append(Frame(x: x, y: y, w: w, h: bounds.y - y))
        }
        if maxY > bounds.maxY {
            parts.append(Frame(x: x, y: bounds.maxY, w: w, h: maxY - bounds.maxY))
        }
        let middleY = Swift.max(y, bounds.y)
        let middleH = Swift.min(maxY, bounds.maxY) - middleY
        if x < bounds.x {
            parts.append(Frame(x: x, y: middleY, w: bounds.x - x, h: middleH))
        }
        if maxX > bounds.maxX {
            parts.append(Frame(x: bounds.maxX, y: middleY, w: maxX - bounds.maxX, h: middleH))
        }
        return parts
    }
}

/// The grid lines the canvas draws while snapping is on (spec Section 4). Drawing only; snapping uses the grid size
/// itself.
public enum GridLines {
    /// The multiples of `grid` from `lower` to `upper`, inclusive.
    public static func positions(from lower: Double, to upper: Double, grid: Int) -> [Int] {
        guard grid > 0, lower <= upper else { return [] }
        let first = Int((lower / Double(grid)).rounded(.up))
        let last = Int((upper / Double(grid)).rounded(.down))
        guard first <= last else { return [] }
        return (first...last).map { $0 * grid }
    }

    /// The spacing between drawn lines: the smallest multiple of `grid` that is at least `minimumSpacing` view points
    /// apart at `zoom`, so the grid thins out instead of filling the view when zoomed out.
    public static func drawnStep(grid: Int, zoom: Double, minimumSpacing: Double = 6) -> Int {
        guard grid > 0, zoom > 0 else { return max(grid, 1) }
        let multiple = max(1, Int((minimumSpacing / (Double(grid) * zoom)).rounded(.up)))
        return grid * multiple
    }
}

/// How the canvas tiles its grid dots over the view: one row of dots, repeated down, starting a little above and left
/// of the view's top-left corner. The counts depend only on the spacing and the view's size, so a pan moves the tiling
/// without changing what it draws.
public struct GridTiling: Equatable, Sendable {
    /// Screen points between drawn lines (`GridLines.drawnStep`).
    public var step: Int
    /// View points between drawn lines.
    public var spacing: Double
    /// The view point of the first line in each direction: the last line at or before the view's top-left corner,
    /// so each coordinate is more than `-spacing` and at most 0.
    public var originX: Double
    public var originY: Double
    /// How many lines in each direction, from the origin past the view's far edge.
    public var columns: Int
    public var rows: Int

    /// The grid's tiling for `camera` over a view `viewSize` big, or nil when there is nothing to draw.
    public init?(grid: Int, camera: Camera, viewSize: CGSize, minimumSpacing: Double) {
        let width = Double(viewSize.width)
        let height = Double(viewSize.height)
        guard grid > 0, width > 0, height > 0 else { return nil }
        let step = GridLines.drawnStep(grid: grid, zoom: camera.zoom, minimumSpacing: minimumSpacing)
        let spacing = Double(step) * camera.zoom
        self.step = step
        self.spacing = spacing
        originX = Self.origin(pan: camera.panX, step: step, zoom: camera.zoom)
        originY = Self.origin(pan: camera.panY, step: step, zoom: camera.zoom)
        // The origin is up to one spacing before the view, so one more line than fits, plus one, reaches past it.
        columns = Int((width / spacing).rounded(.up)) + 2
        rows = Int((height / spacing).rounded(.up)) + 2
    }

    /// The view coordinate of the last line at or before `pan`.
    private static func origin(pan: Double, step: Int, zoom: Double) -> Double {
        let line = (pan / Double(step)).rounded(.down) * Double(step)
        return min((line - pan) * zoom, 0)
    }
}
