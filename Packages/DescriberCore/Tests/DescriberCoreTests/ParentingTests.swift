import XCTest

@testable import DescriberCore

final class ParentingTests: XCTestCase {
    func testDrawingInsideARegionMakesItTheParent() throws {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        let id = RegionID("new")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 140, y: 140, w: 40, h: 40), title: "New", id: id)
            .apply(to: project)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: id)?.id, outer.id)
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "  Inner", "  New", "Side"])
    }

    func testDrawingOverTwoNestedRegionsPicksTheInnerOne() throws {
        let (project, screen, _, inner, _) = Fixtures.nestedProject()
        let id = RegionID("new")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 30, y: 30, w: 20, h: 20), title: "New", id: id)
            .apply(to: project)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: id)?.id, inner.id)
    }

    func testDrawingOutsideEverythingIsTopLevel() throws {
        let (project, screen, _, _, _) = Fixtures.nestedProject()
        let id = RegionID("new")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 0, y: 400, w: 50, h: 50), title: "New", id: id)
            .apply(to: project)
        XCTAssertNil(RegionIndex(screen: screen).parent(of: id))
        XCTAssertEqual(screen.regions.last?.id, id)
    }

    func testEqualSizeCandidatesResolveToTheOneOnTop() {
        let below = Region(id: RegionID("below"), title: "Below", frame: Frame(x: 0, y: 0, w: 100, h: 100))
        let above = Region(id: RegionID("above"), title: "Above", frame: Frame(x: 0, y: 0, w: 100, h: 100))
        let screen = Screen(name: "S", viewport: Viewport(width: 400, height: 400), regions: [below, above])
        XCTAssertEqual(Parenting.parent(for: Frame(x: 10, y: 10, w: 10, h: 10), excluding: nil, in: screen), above.id)

        screen.regions = [above, below]
        XCTAssertEqual(Parenting.parent(for: Frame(x: 10, y: 10, w: 10, h: 10), excluding: nil, in: screen), below.id)
    }

    func testEqualSizeChildIsOnTopOfItsParent() {
        let child = Region(id: RegionID("child"), title: "Child", frame: Frame(x: 0, y: 0, w: 100, h: 100))
        let parent = Region(
            id: RegionID("parent"),
            title: "Parent",
            frame: Frame(x: 0, y: 0, w: 100, h: 100),
            children: [child]
        )
        let screen = Screen(name: "S", viewport: Viewport(width: 400, height: 400), regions: [parent])
        XCTAssertEqual(Parenting.parent(for: Frame(x: 10, y: 10, w: 10, h: 10), excluding: nil, in: screen), child.id)
    }

    func testARegionExactlyTouchingItsParentsEdgesIsContained() throws {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        let id = RegionID("edge")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 0, y: 150, w: 200, h: 50), title: "Edge", id: id)
            .apply(to: project)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: id)?.id, outer.id)
    }

    func testDraggingIntoAndOutOfARegionReparents() throws {
        let (project, screen, outer, _, side) = Fixtures.nestedProject()
        _ = try MoveRegions(screen: screen.id, regions: [side.id], dx: -160, dy: 130).apply(to: project)
        XCTAssertEqual(side.frame, Frame(x: 140, y: 130, w: 100, h: 100))
        XCTAssertNil(RegionIndex(screen: screen).parent(of: side.id), "Pokes out of Outer, so stays top level")

        _ = try MoveRegions(screen: screen.id, regions: [side.id], dx: -40, dy: -30).apply(to: project)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: side.id)?.id, outer.id)
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "  Inner", "  Side"])

        _ = try MoveRegions(screen: screen.id, regions: [side.id], dx: 300, dy: 0).apply(to: project)
        XCTAssertNil(RegionIndex(screen: screen).parent(of: side.id))
        XCTAssertEqual(Fixtures.outline(screen), ["Outer", "  Inner", "Side"])
    }

    func testARegionIsNeverItsOwnOrItsDescendantsChild() {
        let (_, screen, outer, _, _) = Fixtures.nestedProject()
        XCTAssertNil(Parenting.parent(for: outer.frame, excluding: outer.id, in: screen))
    }

    func testScrollingContentAreaContainsChildrenPastTheFrame() throws {
        let (project, screen, outer, _, _) = Fixtures.nestedProject()
        outer.scroll = Scroll(axis: .vertical, contentWidth: 200, contentHeight: 600)
        let id = RegionID("below-fold")
        _ = try CreateRegion(screen: screen.id, frame: Frame(x: 10, y: 400, w: 50, h: 50), title: "Below", id: id)
            .apply(to: project)
        XCTAssertEqual(RegionIndex(screen: screen).parent(of: id)?.id, outer.id)
    }

    func testRegionIndexHelpers() {
        let (_, screen, outer, inner, side) = Fixtures.nestedProject()
        let index = RegionIndex(screen: screen)
        XCTAssertEqual(index.regions.map(\.id), [outer.id, inner.id, side.id])
        XCTAssertEqual(index[inner.id]?.parent, outer.id)
        XCTAssertEqual(index[side.id]?.siblingIndex, 1)
        XCTAssertEqual(index.path(to: inner.id).map(\.id), [outer.id, inner.id])
        XCTAssertEqual(index.descendants(of: outer.id).map(\.id), [inner.id])
    }
}
