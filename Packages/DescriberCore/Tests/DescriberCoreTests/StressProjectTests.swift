import XCTest

@testable import DescriberCore

final class StressProjectTests: XCTestCase {
    func testHasExactlyTheRequestedNumberOfRegions() throws {
        for count in [0, 1, 7, 500] {
            let screen = try XCTUnwrap(Project.stressTest(regionCount: count).screens.first)
            XCTAssertEqual(screen.allRegions.count, count)
        }
    }

    func testEveryRegionIsUnderTheParentTheRulePicks() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let index = RegionIndex(screen: screen)
        XCTAssertEqual(Set(index.regions.map(\.id)).count, 500)
        for region in index.regions {
            XCTAssertEqual(
                index.parent(of: region.id)?.id,
                Parenting.parent(for: region.frame, excluding: region.id, in: screen),
                region.title
            )
            XCTAssertTrue(Geometry.meetsMinimumSize(region.frame))
        }
        XCTAssertGreaterThan(index.regions.filter { !$0.children.isEmpty }.count, 100)
    }

    func testSomeRegionsStraddleOrLeaveTheFrame() throws {
        let screen = try XCTUnwrap(Project.stressTest(regionCount: 500).screens.first)
        let outside = screen.allRegions.filter { !$0.frame.parts(outside: screen.canvasBounds).isEmpty }
        XCTAssertFalse(outside.isEmpty)
        XCTAssertTrue(outside.contains { $0.frame.intersects(screen.canvasBounds) })
    }

    func testRoundTripsThroughThePackageFormat() throws {
        let tree = ProjectPackage.write(project: Project.stressTest(regionCount: 500)).tree
        XCTAssertEqual(ProjectPackage.write(project: try ProjectPackage.read(tree)).tree, tree)
    }
}
