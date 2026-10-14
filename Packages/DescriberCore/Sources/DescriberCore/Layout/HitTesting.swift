import Foundation

// On Apple platforms CGRect's geometry lives in CoreGraphics; on Linux, Foundation has it all.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Which regions lie under a point or a rectangle on a screen. Points and rectangles are in screen points.
public enum HitTesting {
    /// The topmost region whose frame contains `point`, edges included. Later in the draw order is on top.
    public static func region(at point: CGPoint, in screen: Screen) -> RegionID? {
        RegionIndex(screen: screen).regions.last { $0.frame.cgRect.containsIncludingEdges(point) }?.id
    }

    /// Every region `rect` overlaps, in draw order: the regions a marquee touches (spec Section 7). A rectangle with
    /// no width or height touches nothing.
    public static func regions(touching rect: CGRect, in screen: Screen) -> [RegionID] {
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0 else { return [] }
        return RegionIndex(screen: screen).regions.filter { $0.frame.cgRect.intersects(rect) }.map(\.id)
    }
}

/// One of the eight handles on a selected region: four corners and four edge midpoints.
public enum ResizeHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    /// The edges dragging this handle moves.
    public var edges: Snapping.Edges {
        switch self {
        case .topLeft: [.top, .left]
        case .top: .top
        case .topRight: [.top, .right]
        case .right: .right
        case .bottomRight: [.bottom, .right]
        case .bottom: .bottom
        case .bottomLeft: [.bottom, .left]
        case .left: .left
        }
    }

    /// Whether the handle is on a corner, so it drags two edges.
    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        default: false
        }
    }

    /// Where the handle sits on `rect`.
    public func point(on rect: CGRect) -> CGPoint {
        let x: CGFloat = edges.contains(.left) ? rect.minX : edges.contains(.right) ? rect.maxX : rect.midX
        let y: CGFloat = edges.contains(.top) ? rect.minY : edges.contains(.bottom) ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }

    /// The handle of `rect` nearest `point`, if one is within `radius` along both axes. On a rectangle too small to
    /// tell the handles apart, the nearest one wins, and corners win ties so a tiny region can still grow both ways.
    public static func handle(at point: CGPoint, on rect: CGRect, radius: Double) -> ResizeHandle? {
        var best: (handle: ResizeHandle, distance: Double)?
        for handle in allCases {
            let center = handle.point(on: rect)
            let dx = Double(abs(point.x - center.x))
            let dy = Double(abs(point.y - center.y))
            guard dx <= radius, dy <= radius else { continue }
            let distance = dx * dx + dy * dy
            if let current = best, current.distance < distance || (current.distance == distance && !handle.isCorner) {
                continue
            }
            best = (handle, distance)
        }
        return best?.handle
    }
}

extension CGRect {
    /// `contains(_:)` leaves out the right and bottom edges; hit testing includes them.
    func containsIncludingEdges(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
