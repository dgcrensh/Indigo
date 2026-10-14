import Foundation

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
