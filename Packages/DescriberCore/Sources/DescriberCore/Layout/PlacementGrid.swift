import Foundation

/// The regions of a `ScrollLayout` by where their drawn content areas are, so parenting checks only the regions that
/// could hold a frame instead of every region on the screen.
///
/// The screen is cut into square cells. Each cell lists, in draw order, the regions whose drawn content area overlaps
/// it, edges included. A content area that holds a frame holds the frame's origin, so every region that could be its
/// parent is listed in the cell of that point. A content area spanning more than `maximumCells` cells goes in one list
/// shared by every cell instead, so a huge scrolling region doesn't fill thousands of cells.
struct PlacementGrid {
    /// Cells are 256 points square (1 << 8), about one container in the stress project.
    static let cellShift = 8
    static let maximumCells = 64

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private var cells: [Cell: [Int]] = [:]
    /// The regions too large for the cells, in draw order.
    private var everywhere: [Int] = []

    /// Adds the region at draw order `position`, which must come after every position added so far.
    mutating func add(_ position: Int, content: Frame) {
        let minX = Self.cell(Swift.min(content.x, content.maxX))
        let maxX = Self.cell(Swift.max(content.x, content.maxX))
        let minY = Self.cell(Swift.min(content.y, content.maxY))
        let maxY = Self.cell(Swift.max(content.y, content.maxY))
        let columns = maxX - minX + 1
        let rows = maxY - minY + 1
        guard columns <= Self.maximumCells, rows <= Self.maximumCells, columns * rows <= Self.maximumCells else {
            everywhere.append(position)
            return
        }
        for y in minY...maxY {
            for x in minX...maxX {
                cells[Cell(x: x, y: y), default: []].append(position)
            }
        }
    }

    /// Calls `body` in draw order with each region whose content area could hold a frame with its origin at `x`, `y`.
    func forEachCandidate(atX x: Int, y: Int, _ body: (Int) -> Void) {
        let cell = cells[Cell(x: Self.cell(x), y: Self.cell(y))] ?? []
        var next = 0
        for position in everywhere {
            while next < cell.count, cell[next] < position {
                body(cell[next])
                next += 1
            }
            body(position)
        }
        while next < cell.count {
            body(cell[next])
            next += 1
        }
    }

    /// The cell holding coordinate `value`. The shift rounds down for negative coordinates too.
    private static func cell(_ value: Int) -> Int {
        value >> cellShift
    }
}
