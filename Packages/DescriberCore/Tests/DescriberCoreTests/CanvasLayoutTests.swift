import XCTest

@testable import DescriberCore

final class CanvasLayoutTests: XCTestCase {
    private let bounds = Frame(x: 0, y: 0, w: 100, h: 200)

    /// Checks that `parts` don't overlap, lie outside `bounds`, and together cover the frame's area outside it.
    private func assertParts(of frame: Frame, file: StaticString = #filePath, line: UInt = #line) {
        let parts = frame.parts(outside: bounds)
        for (i, part) in parts.enumerated() {
            XCTAssertTrue(frame.contains(part), file: file, line: line)
            XCTAssertFalse(part.intersects(bounds), file: file, line: line)
            for other in parts[(i + 1)...] {
                XCTAssertFalse(part.intersects(other), file: file, line: line)
            }
        }
        let inside = clipped(frame, to: bounds)?.area ?? 0
        XCTAssertEqual(parts.map(\.area).reduce(0, +), frame.area - inside, file: file, line: line)
    }

    private func clipped(_ frame: Frame, to bounds: Frame) -> Frame? {
        let x = max(frame.x, bounds.x)
        let y = max(frame.y, bounds.y)
        let maxX = min(frame.maxX, bounds.maxX)
        let maxY = min(frame.maxY, bounds.maxY)
        return maxX > x && maxY > y ? Frame(x: x, y: y, w: maxX - x, h: maxY - y) : nil
    }

    func testAFrameInsideHasNoPartsOutside() {
        XCTAssertEqual(Frame(x: 10, y: 10, w: 50, h: 50).parts(outside: bounds), [])
        XCTAssertEqual(bounds.parts(outside: bounds), [])
    }

    func testAFrameFullyOutsideIsOnePart() {
        let frame = Frame(x: 150, y: 10, w: 20, h: 20)
        XCTAssertEqual(frame.parts(outside: bounds), [frame])
        // Touching the edge is still outside.
        let touching = Frame(x: 100, y: 0, w: 10, h: 10)
        XCTAssertEqual(touching.parts(outside: bounds), [touching])
    }

    func testAFrameStraddlingTheRightEdge() {
        XCTAssertEqual(Frame(x: 80, y: 20, w: 40, h: 10).parts(outside: bounds), [Frame(x: 100, y: 20, w: 20, h: 10)])
    }

    func testPartsCoverTheAreaOutsideWithoutOverlap() {
        let frames = [
            Frame(x: -10, y: -10, w: 30, h: 30),
            Frame(x: -20, y: -20, w: 200, h: 300),
            Frame(x: 90, y: 190, w: 40, h: 40),
            Frame(x: 20, y: -5, w: 10, h: 300),
            Frame(x: -50, y: 50, w: 300, h: 10),
            Frame(x: 50, y: 150, w: 10, h: 10),
        ]
        for frame in frames {
            assertParts(of: frame)
        }
    }

    func testIntersectsNeedsSharedArea() {
        XCTAssertTrue(Frame(x: 0, y: 0, w: 10, h: 10).intersects(Frame(x: 9, y: 9, w: 10, h: 10)))
        XCTAssertFalse(Frame(x: 0, y: 0, w: 10, h: 10).intersects(Frame(x: 10, y: 0, w: 10, h: 10)))
        XCTAssertFalse(Frame(x: 0, y: 0, w: 10, h: 10).intersects(Frame(x: -20, y: -20, w: 5, h: 5)))
    }

    func testCanvasBoundsAreTheViewportOrTheContentArea() {
        let screen = Screen(name: "Feed", viewport: Viewport(width: 393, height: 852))
        XCTAssertEqual(screen.viewportFrame, Frame(x: 0, y: 0, w: 393, h: 852))
        XCTAssertEqual(screen.canvasBounds, screen.viewportFrame)
        screen.scroll = Scroll(axis: .vertical, contentWidth: 393, contentHeight: 2400)
        XCTAssertEqual(screen.canvasBounds, Frame(x: 0, y: 0, w: 393, h: 2400))
        XCTAssertEqual(screen.viewportFrame, Frame(x: 0, y: 0, w: 393, h: 852))
    }

    func testGridLinePositions() {
        XCTAssertEqual(GridLines.positions(from: 0, to: 32, grid: 8), [0, 8, 16, 24, 32])
        XCTAssertEqual(GridLines.positions(from: -9.5, to: 10, grid: 8), [-8, 0, 8])
        XCTAssertEqual(GridLines.positions(from: 1, to: 7, grid: 8), [])
        XCTAssertEqual(GridLines.positions(from: 10, to: 0, grid: 8), [])
    }

    func testGridLinesThinOutWhenTooClose() {
        XCTAssertEqual(GridLines.drawnStep(grid: 8, zoom: 1), 8)
        XCTAssertEqual(GridLines.drawnStep(grid: 8, zoom: 0.75), 8)  // exactly 6 points apart
        XCTAssertEqual(GridLines.drawnStep(grid: 8, zoom: 0.5), 16)
        XCTAssertEqual(GridLines.drawnStep(grid: 4, zoom: 0.1), 60)
        XCTAssertEqual(GridLines.drawnStep(grid: 32, zoom: 0.1), 64)
        for zoom in [0.1, 0.13, 0.4, 1, 3] {
            let step = GridLines.drawnStep(grid: 12, zoom: zoom)
            XCTAssertEqual(step % 12, 0)
            XCTAssertGreaterThanOrEqual(Double(step) * zoom, 6 - 1e-9)
            XCTAssertLessThan(Double(step - 12) * zoom, 6)
        }
    }
}
