import XCTest

@testable import DescriberCore

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

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

    func testGridTilingStartsAtTheLastLineBeforeTheView() throws {
        let tiling = try XCTUnwrap(
            GridTiling(
                grid: 8, camera: Camera(zoom: 2, panX: 13, panY: -3), viewSize: CGSize(width: 100, height: 50),
                minimumSpacing: 10))
        XCTAssertEqual(tiling.step, 8)
        XCTAssertEqual(tiling.spacing, 16)
        // Lines at x = 8 and y = -8, drawn at (8 − 13) × 2 and (−8 + 3) × 2.
        XCTAssertEqual(tiling.originX, -10)
        XCTAssertEqual(tiling.originY, -10)
        XCTAssertEqual(tiling.columns, 9)
        XCTAssertEqual(tiling.rows, 6)
        XCTAssertGreaterThanOrEqual(tiling.originX + Double(tiling.columns - 1) * tiling.spacing, 100)
        XCTAssertGreaterThanOrEqual(tiling.originY + Double(tiling.rows - 1) * tiling.spacing, 50)
    }

    func testGridTilingPutsALineOnTheEdgeAtZero() throws {
        let tiling = try XCTUnwrap(
            GridTiling(
                grid: 8, camera: Camera(zoom: 1, panX: 16, panY: 0), viewSize: CGSize(width: 64, height: 64),
                minimumSpacing: 6))
        XCTAssertEqual(tiling.originX, 0)
        XCTAssertEqual(tiling.originY, 0)
    }

    func testPanningMovesTheGridTilingWithoutChangingItsCounts() throws {
        let size = CGSize(width: 1440, height: 900)
        let base = try XCTUnwrap(GridTiling(grid: 8, camera: Camera(zoom: 1.37), viewSize: size, minimumSpacing: 10))
        for offset in stride(from: -40.0, through: 40, by: 0.7) {
            let camera = Camera(zoom: 1.37, panX: offset, panY: offset * 3)
            let tiling = try XCTUnwrap(GridTiling(grid: 8, camera: camera, viewSize: size, minimumSpacing: 10))
            XCTAssertEqual(tiling.columns, base.columns)
            XCTAssertEqual(tiling.rows, base.rows)
            XCTAssertEqual(tiling.spacing, base.spacing)
            XCTAssertLessThanOrEqual(tiling.originX, 0)
            XCTAssertGreaterThan(tiling.originX, -tiling.spacing)
            XCTAssertLessThanOrEqual(tiling.originY, 0)
            XCTAssertGreaterThan(tiling.originY, -tiling.spacing)
        }
    }

    func testGridTilingIsNilWithNothingToDraw() {
        XCTAssertNil(GridTiling(grid: 8, camera: Camera(), viewSize: .zero, minimumSpacing: 10))
        XCTAssertNil(GridTiling(grid: 0, camera: Camera(), viewSize: CGSize(width: 10, height: 10), minimumSpacing: 10))
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

    // MARK: Coverage (milestone 20)

    private let viewSize = CGSize(width: 1440, height: 900)

    func testTheCoveredRectIsTheVisibleRectWithHalfAViewAround() {
        let coverage = CanvasCoverage(camera: Camera(zoom: 2, panX: 100, panY: 50), viewSize: viewSize)
        XCTAssertEqual(coverage.visible, CGRect(x: 100, y: 50, width: 720, height: 450))
        XCTAssertEqual(coverage.covered, CGRect(x: -260, y: -175, width: 1440, height: 900))
        XCTAssertTrue(coverage.covered.contains(coverage.visible))
        XCTAssertFalse(coverage.needsRecompute(visible: coverage.visible))
    }

    func testAPanInsideTheMarginNeedsNoRecompute() {
        let camera = Camera(zoom: 1)
        let coverage = CanvasCoverage(camera: camera, viewSize: viewSize)
        for (dx, dy) in [(700.0, 0.0), (-720, 0), (0, 450), (0, -440), (500, -300)] {
            let panned = camera.panned(byViewDX: dx, dy: dy)
            XCTAssertFalse(coverage.needsRecompute(for: panned, viewSize: viewSize), "\(dx), \(dy)")
        }
        for (dx, dy) in [(721.0, 0.0), (-730, 0), (0, 451), (0, -460), (800, 500)] {
            let panned = camera.panned(byViewDX: dx, dy: dy)
            XCTAssertTrue(coverage.needsRecompute(for: panned, viewSize: viewSize), "\(dx), \(dy)")
        }
    }

    func testAZoomAlwaysNeedsARecompute() {
        let camera = Camera(zoom: 1)
        let coverage = CanvasCoverage(camera: camera, viewSize: viewSize)
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        XCTAssertTrue(coverage.needsRecompute(for: camera.zoomed(to: 1.01, anchor: center), viewSize: viewSize))
        XCTAssertTrue(coverage.needsRecompute(for: camera.zoomed(to: 0.99, anchor: center), viewSize: viewSize))
        XCTAssertFalse(coverage.needsRecompute(for: camera, viewSize: viewSize))
    }

    func testRegionsIntersectingARectOverTheFirstContainer() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let container = try XCTUnwrap(screen.regions.first)
        let rect = container.frame.cgRect
        let layout = ScrollLayout(screen: screen)
        let positions = layout.regions(intersecting: rect)
        XCTAssertEqual(positions, Array(0...20), "the container, its five rows and their fifteen items")
        let subtree = [container] + container.children.flatMap { [$0] + $0.children }
        XCTAssertEqual(positions.map { layout.index.regions[$0].id }, subtree.map(\.id))
        XCTAssertEqual(layout.regions(intersecting: CGRect(x: 2000, y: 0, width: 100, height: 100)), [])
        XCTAssertEqual(layout.regions(intersecting: CGRect(x: 20, y: 20, width: 0, height: 100)), [])
    }

    func testRegionsIntersectingLeaveOutChildrenScrolledOutOfView() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let container = try XCTUnwrap(screen.regions.first)
        container.scroll = Scroll(axis: .vertical, contentWidth: 340, contentHeight: 600)
        let layout = ScrollLayout(screen: screen, offsets: [container.id: ScrollOffset(x: 0, y: 200)])
        let ids = layout.regions(intersecting: container.frame.cgRect).map { layout.index.regions[$0].id }
        // Rows 1 to 3 sit above the container's frame once it is scrolled 200 points; rows 4 and 5 still show.
        let shown = [container] + container.children[3...].flatMap { [$0] + $0.children }
        XCTAssertEqual(ids, shown.map(\.id))
        let row1 = container.children[0]
        XCTAssertNil(layout.visibleFrame(of: row1.id))
        XCTAssertFalse(ids.contains(row1.id))
    }

    func testVisibleRegionsAreTheOnesARectAroundThemAllIntersects() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let container = try XCTUnwrap(screen.regions.first)
        container.scroll = Scroll(axis: .vertical, contentWidth: 340, contentHeight: 600)
        let layout = ScrollLayout(screen: screen, offsets: [container.id: ScrollOffset(x: 0, y: 200)])
        let visible = layout.visibleRegions()
        XCTAssertEqual(visible.positions, layout.regions(intersecting: visible.extent.insetBy(dx: -1, dy: -1)))
        XCTAssertEqual(visible.positions.count, 500 - 12, "rows 1 to 3 of the first container and their items")
        XCTAssertEqual(visible.extent.minX, 16)
        XCTAssertEqual(visible.extent.minY, 16)
    }
}
