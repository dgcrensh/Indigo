import XCTest

@testable import DescriberCore

final class SnappingTests: XCTestCase {
    func testSnapRoundsToTheNearestMultiple() {
        XCTAssertEqual(Snapping.snap(0, grid: 8), 0)
        XCTAssertEqual(Snapping.snap(3, grid: 8), 0)
        XCTAssertEqual(Snapping.snap(4, grid: 8), 8)
        XCTAssertEqual(Snapping.snap(13, grid: 8), 16)
        XCTAssertEqual(Snapping.snap(17, grid: 12), 12)
        XCTAssertEqual(Snapping.snap(5, grid: 1), 5)
    }

    func testSnapNegativeCoordinates() {
        XCTAssertEqual(Snapping.snap(-3, grid: 8), 0)
        XCTAssertEqual(Snapping.snap(-4, grid: 8), 0)
        XCTAssertEqual(Snapping.snap(-5, grid: 8), -8)
        XCTAssertEqual(Snapping.snap(-12, grid: 8), -8)
        XCTAssertEqual(Snapping.snap(-13, grid: 8), -16)
        XCTAssertEqual(Snapping.snap(-30, grid: 16), -32)
    }

    func testDrawSnapsEveryEdge() {
        let frame = Frame(x: 3, y: 13, w: 30, h: 22)  // edges 3, 33 and 13, 35
        XCTAssertEqual(Snapping.snap(frame: frame, grid: 8, mode: .draw), Frame(x: 0, y: 16, w: 32, h: 16))
    }

    func testMoveSnapsTheOriginAndKeepsTheSize() {
        let frame = Frame(x: 13, y: -5, w: 30, h: 22)
        XCTAssertEqual(Snapping.snap(frame: frame, grid: 8, mode: .move), Frame(x: 16, y: -8, w: 30, h: 22))
    }

    func testResizeSnapsOnlyTheDraggedEdges() {
        let frame = Frame(x: 3, y: 5, w: 30, h: 30)  // right edge 33, bottom edge 35
        XCTAssertEqual(
            Snapping.snap(frame: frame, grid: 8, mode: .resize([.right])),
            Frame(x: 3, y: 5, w: 29, h: 30)
        )
        XCTAssertEqual(
            Snapping.snap(frame: frame, grid: 8, mode: .resize([.left, .top])),
            Frame(x: 0, y: 8, w: 33, h: 27)
        )
    }

    func testSnappingIsActiveWhenEnabledXorOptionHeld() {
        XCTAssertTrue(Snapping.isActive(enabled: true, optionHeld: false))
        XCTAssertFalse(Snapping.isActive(enabled: true, optionHeld: true))
        XCTAssertFalse(Snapping.isActive(enabled: false, optionHeld: false))
        XCTAssertTrue(Snapping.isActive(enabled: false, optionHeld: true))
    }

    func testGridStepsAndNudgeDistances() {
        XCTAssertEqual(Snapping.gridSteps, [4, 8, 12, 16, 24, 32])
        XCTAssertEqual(Snapping.nudgeDistance(grid: 8, snapping: true, shift: false), 8)
        XCTAssertEqual(Snapping.nudgeDistance(grid: 8, snapping: true, shift: true), 32)
        XCTAssertEqual(Snapping.nudgeDistance(grid: 8, snapping: false, shift: false), 1)
        XCTAssertEqual(Snapping.nudgeDistance(grid: 8, snapping: false, shift: true), 4)
    }

    func testChangingOnlyTheGridSizeChangesNoFrame() {
        let project = AcmeExample.make()
        let before = Fixtures.bytes(project)
        for screen in project.screens {
            project.editorState.screens[screen.id, default: ScreenEditorState()].gridSize = 32
        }
        let after = Fixtures.bytes(project)
        for (path, data) in before {
            XCTAssertEqual(after[path], data, path)
        }
    }

    func testRoundingFractionalFrames() {
        XCTAssertEqual(Frame(rounding: 10.4, y: 10.6, w: 20.4, h: 20.2), Frame(x: 10, y: 11, w: 21, h: 20))
        XCTAssertEqual(Frame(rounding: -0.6, y: 0, w: 4.2, h: 4), Frame(x: -1, y: 0, w: 5, h: 4))
    }
}
