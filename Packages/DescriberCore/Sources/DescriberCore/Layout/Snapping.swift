import Foundation

/// Snapping to the grid (spec Sections 5 and 9). The grid only affects snapping inside commands that draw, move or
/// resize; changing the grid size never changes a stored frame.
public enum Snapping {
    /// The grid sizes the `G` slider offers, in points.
    public static let gridSteps = [4, 8, 12, 16, 24, 32]
    /// The grid size a screen uses when neither its editor state nor settings (`AppSettings.gridSize`) give one.
    public static let defaultGridSize = 8

    /// The edges a resize drags.
    public struct Edges: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let left = Edges(rawValue: 1 << 0)
        public static let right = Edges(rawValue: 1 << 1)
        public static let top = Edges(rawValue: 1 << 2)
        public static let bottom = Edges(rawValue: 1 << 3)
        public static let all: Edges = [.left, .right, .top, .bottom]
    }

    public enum Mode: Hashable, Sendable {
        /// Drawing a new region: every edge snaps.
        case draw
        /// Moving: the origin snaps and the size is kept.
        case move
        /// Resizing: only the dragged edges snap.
        case resize(Edges)
    }

    /// Snapping applies when it is enabled and Option is not held, or disabled and Option is held.
    public static func isActive(enabled: Bool, optionHeld: Bool) -> Bool {
        enabled != optionHeld
    }

    /// The nearest multiple of `grid`. Halfway values round up (toward positive infinity), for negative values too.
    public static func snap(_ value: Int, grid: Int) -> Int {
        guard grid > 1 else { return value }
        let shifted = value + grid / 2
        let quotient = shifted >= 0 ? shifted / grid : -((-shifted + grid - 1) / grid)
        return quotient * grid
    }

    public static func snap(frame: Frame, grid: Int, mode: Mode) -> Frame {
        switch mode {
        case .draw:
            return snapEdges(frame, grid: grid, edges: .all)
        case .move:
            return Frame(x: snap(frame.x, grid: grid), y: snap(frame.y, grid: grid), w: frame.w, h: frame.h)
        case .resize(let edges):
            return snapEdges(frame, grid: grid, edges: edges)
        }
    }

    private static func snapEdges(_ frame: Frame, grid: Int, edges: Edges) -> Frame {
        let minX = edges.contains(.left) ? snap(frame.x, grid: grid) : frame.x
        let maxX = edges.contains(.right) ? snap(frame.maxX, grid: grid) : frame.maxX
        let minY = edges.contains(.top) ? snap(frame.y, grid: grid) : frame.y
        let maxY = edges.contains(.bottom) ? snap(frame.maxY, grid: grid) : frame.maxY
        return Frame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    /// How far an arrow key moves the selection: one grid step, or four with Shift; 1 pt and 4 pt when snapping is
    /// off.
    public static func nudgeDistance(grid: Int, snapping: Bool, shift: Bool) -> Int {
        (snapping ? grid : 1) * (shift ? 4 : 1)
    }
}
