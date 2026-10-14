import XCTest

@testable import DescriberCore

final class HitTestingTests: XCTestCase {
    func testThePointPicksTheTopmostRegion() {
        let (_, screen, outer, inner, side) = Fixtures.nestedProject()
        XCTAssertEqual(HitTesting.region(at: CGPoint(x: 50, y: 50), in: screen), inner.id)
        XCTAssertEqual(HitTesting.region(at: CGPoint(x: 150, y: 150), in: screen), outer.id)
        XCTAssertEqual(HitTesting.region(at: CGPoint(x: 400, y: 100), in: screen), side.id, "edges count")
        XCTAssertNil(HitTesting.region(at: CGPoint(x: 250, y: 50), in: screen))
    }

    func testALaterSiblingIsOnTop() {
        let (_, screen, outer, _, _) = Fixtures.nestedProject()
        let overlap = Region(id: RegionID("overlap"), title: "Overlap", frame: Frame(x: 100, y: 100, w: 50, h: 50))
        outer.children.append(overlap)
        XCTAssertEqual(HitTesting.region(at: CGPoint(x: 110, y: 110), in: screen), overlap.id)
    }

    func testTheMarqueePicksEveryRegionItTouches() {
        let (_, screen, outer, inner, side) = Fixtures.nestedProject()
        XCTAssertEqual(
            HitTesting.regions(touching: CGRect(x: 110, y: 50, width: 200, height: 10), in: screen),
            [outer.id, inner.id, side.id])
        XCTAssertEqual(
            HitTesting.regions(touching: CGRect(x: 190, y: 190, width: -20, height: -20), in: screen), [outer.id],
            "a rectangle dragged up and left")
        XCTAssertEqual(HitTesting.regions(touching: CGRect(x: 210, y: 0, width: 80, height: 300), in: screen), [])
        XCTAssertEqual(HitTesting.regions(touching: CGRect(x: 50, y: 50, width: 0, height: 0), in: screen), [])
    }

    func testHandles() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(ResizeHandle.handle(at: CGPoint(x: 2, y: -3), on: rect, radius: 5), .topLeft)
        XCTAssertEqual(ResizeHandle.handle(at: CGPoint(x: 50, y: 50), on: rect, radius: 5), .bottom)
        XCTAssertEqual(ResizeHandle.handle(at: CGPoint(x: 104, y: 25), on: rect, radius: 5), .right)
        XCTAssertNil(ResizeHandle.handle(at: CGPoint(x: 50, y: 25), on: rect, radius: 5))
        XCTAssertEqual(ResizeHandle.topRight.edges, [.top, .right])
        XCTAssertEqual(ResizeHandle.left.point(on: rect), CGPoint(x: 0, y: 25))
    }

    func testATinyRegionsCornerWinsTies() {
        let rect = CGRect(x: 0, y: 0, width: 4, height: 4)
        XCTAssertEqual(ResizeHandle.handle(at: CGPoint(x: 5, y: 5), on: rect, radius: 6), .bottomRight)
        XCTAssertEqual(ResizeHandle.handle(at: CGPoint(x: 1, y: 1), on: rect, radius: 6), .topLeft)
    }
}
