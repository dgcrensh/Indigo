import XCTest

@testable import DescriberCore

final class CanvasGestureTests: XCTestCase {
    private typealias Nested = (project: Project, screen: Screen, outer: Region, inner: Region, side: Region)

    private func context(
        _ fixture: Nested, tool: Tool = .select, selection: [RegionID] = [], snapping: Bool = true, zoom: Double = 1
    ) -> GestureContext {
        GestureContext(
            screen: fixture.screen, tool: tool, selection: selection, snappingEnabled: snapping, gridSize: 8,
            zoom: zoom)
    }

    /// Presses at `from`, drags through the midpoint to `to`, releases, and returns the gesture and its command.
    private func gesture(
        _ context: GestureContext, from: CGPoint, to: CGPoint, modifiers: KeyCombo.Modifiers = [],
        optionHeld: Bool = false
    ) -> (CanvasGesture, Command?) {
        var gesture = CanvasGesture(pressAt: from, modifiers: modifiers, context: context)
        gesture.drag(to: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), optionHeld: optionHeld)
        gesture.drag(to: to, optionHeld: optionHeld)
        let command = gesture.release(at: to, optionHeld: optionHeld)
        return (gesture, command)
    }

    private func frames(after command: Command?, on fixture: Nested) throws -> [RegionID: Frame] {
        let command = try XCTUnwrap(command)
        try EditSession(project: fixture.project).perform(command)
        return Dictionary(uniqueKeysWithValues: fixture.screen.allRegions.map { ($0.id, $0.frame) })
    }

    // MARK: Region tool

    func testARegionToolDragCreatesOneSnappedRegion() throws {
        let fixture = Fixtures.nestedProject()
        let (gesture, command) = gesture(
            context(fixture, tool: .region), from: CGPoint(x: 31, y: 33), to: CGPoint(x: 77, y: 58))
        let create = try XCTUnwrap(command as? CreateRegion)
        XCTAssertEqual(create.frame, Frame(x: 32, y: 32, w: 48, h: 24))
        XCTAssertEqual(create.title, "Region")
        XCTAssertEqual(gesture.selection, [create.id])
        XCTAssertEqual(gesture.preview, .none)

        try EditSession(project: fixture.project).perform(create)
        XCTAssertEqual(RegionIndex(screen: fixture.screen).parent(of: create.id)?.id, fixture.inner.id)
    }

    func testARegionToolDragPreviewsTheFrameItWillCreate() {
        let fixture = Fixtures.nestedProject()
        var gesture = CanvasGesture(pressAt: CGPoint(x: 77, y: 58), context: context(fixture, tool: .region))
        gesture.drag(to: CGPoint(x: 31, y: 33))
        XCTAssertEqual(gesture.preview, .newRegion(Frame(x: 32, y: 32, w: 48, h: 24)), "dragged up and left")
    }

    func testADragUnderTheMinimumSizeCreatesNothing() {
        let fixture = Fixtures.nestedProject()
        let (_, command) = gesture(
            context(fixture, tool: .region), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 13.5, y: 40))
        XCTAssertNil(command)
    }

    func testSnappingThatCollapsesASideSpansAGridStep() {
        XCTAssertEqual(
            CanvasGesture.drawnFrame(from: CGPoint(x: 5, y: 9), to: CGPoint(x: 9, y: 40), grid: 8),
            Frame(x: 8, y: 8, w: 8, h: 32))
        XCTAssertEqual(
            CanvasGesture.drawnFrame(from: CGPoint(x: 9, y: 40), to: CGPoint(x: 5, y: 9), grid: 8),
            Frame(x: 0, y: 8, w: 8, h: 32), "dragged left, so the side grows left")
    }

    func testOptionInvertsSnappingForTheGesture() throws {
        let fixture = Fixtures.nestedProject()
        let from = CGPoint(x: 31, y: 33)
        let to = CGPoint(x: 77, y: 58)
        let free = gesture(context(fixture, tool: .region), from: from, to: to, optionHeld: true).1
        XCTAssertEqual((free as? CreateRegion)?.frame, Frame(x: 31, y: 33, w: 46, h: 25))

        let off = gesture(context(fixture, tool: .region, snapping: false), from: from, to: to).1
        XCTAssertEqual((off as? CreateRegion)?.frame, Frame(x: 31, y: 33, w: 46, h: 25))
        let inverted = gesture(context(fixture, tool: .region, snapping: false), from: from, to: to, optionHeld: true)
        XCTAssertEqual((inverted.1 as? CreateRegion)?.frame, Frame(x: 32, y: 32, w: 48, h: 24))
    }

    // MARK: Select tool: clicks

    func testAClickSelectsTheTopmostRegion() {
        let fixture = Fixtures.nestedProject()
        let (gesture, command) = gesture(context(fixture), from: CGPoint(x: 50, y: 50), to: CGPoint(x: 51, y: 50))
        XCTAssertNil(command)
        XCTAssertFalse(gesture.isDragging, "1 pt is under the drag threshold")
        XCTAssertEqual(gesture.selection, [fixture.inner.id])
    }

    func testShiftClickTogglesARegion() {
        let fixture = Fixtures.nestedProject()
        let point = CGPoint(x: 350, y: 50)
        let added = gesture(
            context(fixture, selection: [fixture.inner.id]), from: point, to: point, modifiers: .shift
        ).0
        XCTAssertEqual(added.selection, [fixture.inner.id, fixture.side.id])
        let removed = gesture(
            context(fixture, selection: [fixture.inner.id, fixture.side.id]), from: point, to: point,
            modifiers: .shift
        ).0
        XCTAssertEqual(removed.selection, [fixture.inner.id])
    }

    func testAClickOnEmptyCanvasClearsTheSelection() {
        let fixture = Fixtures.nestedProject()
        let point = CGPoint(x: 250, y: 400)
        XCTAssertEqual(gesture(context(fixture, selection: [fixture.side.id]), from: point, to: point).0.selection, [])
        let kept = gesture(context(fixture, selection: [fixture.side.id]), from: point, to: point, modifiers: .shift)
        XCTAssertEqual(kept.0.selection, [fixture.side.id])
    }

    func testAClickInsideAMultiSelectionSelectsJustThatRegion() {
        let fixture = Fixtures.nestedProject()
        let selection = [fixture.inner.id, fixture.side.id]
        var gesture = CanvasGesture(pressAt: CGPoint(x: 350, y: 50), context: context(fixture, selection: selection))
        XCTAssertEqual(gesture.selection, selection, "the press keeps the selection so it can be dragged")
        XCTAssertNil(gesture.release(at: CGPoint(x: 350, y: 50)))
        XCTAssertEqual(gesture.selection, [fixture.side.id])
    }

    // MARK: Select tool: moving

    func testDraggingARegionMovesTheWholeSelectionInOneCommand() throws {
        let fixture = Fixtures.nestedProject()
        let selection = [fixture.outer.id, fixture.side.id]
        let (gesture, command) = gesture(
            context(fixture, selection: selection), from: CGPoint(x: 350, y: 50), to: CGPoint(x: 361, y: 69))
        let move = try XCTUnwrap(command as? MoveRegions)
        XCTAssertEqual(move.regions, [fixture.side.id, fixture.outer.id], "the grabbed region leads")
        XCTAssertEqual(gesture.selection, selection)

        let frames = try frames(after: move, on: fixture)
        XCTAssertEqual(frames[fixture.side.id], Frame(x: 312, y: 16, w: 100, h: 100))
        XCTAssertEqual(frames[fixture.outer.id], Frame(x: 12, y: 16, w: 200, h: 200))
        XCTAssertEqual(frames[fixture.inner.id], Frame(x: 32, y: 36, w: 100, h: 100), "children move along")
    }

    func testTheMovePreviewMatchesTheResult() throws {
        let fixture = Fixtures.nestedProject()
        var gesture = CanvasGesture(pressAt: CGPoint(x: 150, y: 150), context: context(fixture))
        gesture.drag(to: CGPoint(x: 163, y: 147))
        guard case .frames(let preview) = gesture.preview else { return XCTFail("no preview") }
        XCTAssertEqual(Set(preview.keys), [fixture.outer.id, fixture.inner.id])
        let command = gesture.release(at: CGPoint(x: 163, y: 147))
        let frames = try frames(after: command, on: fixture)
        for (id, frame) in preview {
            XCTAssertEqual(frames[id], frame)
        }
    }

    func testDraggingAnUnselectedRegionSelectsAndMovesIt() throws {
        let fixture = Fixtures.nestedProject()
        let (gesture, command) = gesture(
            context(fixture, selection: [fixture.side.id]), from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 90))
        XCTAssertEqual(gesture.selection, [fixture.inner.id])
        XCTAssertEqual((command as? MoveRegions)?.regions, [fixture.inner.id])
    }

    func testAMoveThatSnapsBackCommitsNothing() {
        let fixture = Fixtures.nestedProject()
        let (gesture, command) = gesture(context(fixture), from: CGPoint(x: 150, y: 150), to: CGPoint(x: 153, y: 151))
        XCTAssertTrue(gesture.isDragging)
        XCTAssertNil(command, "the outer region's origin snaps back to 0, 0")
    }

    func testShiftClickThatDeselectsDoesNotMove() {
        let fixture = Fixtures.nestedProject()
        let (gesture, command) = gesture(
            context(fixture, selection: [fixture.side.id, fixture.inner.id]), from: CGPoint(x: 350, y: 50),
            to: CGPoint(x: 380, y: 90), modifiers: .shift)
        XCTAssertNil(command)
        XCTAssertEqual(gesture.selection, [fixture.inner.id])
    }

    // MARK: Select tool: marquee

    func testDraggingOnEmptyCanvasSelectsEveryRegionTheMarqueeTouches() {
        let fixture = Fixtures.nestedProject()
        var gesture = CanvasGesture(pressAt: CGPoint(x: 250, y: 300), context: context(fixture, selection: []))
        gesture.drag(to: CGPoint(x: 110, y: 150))
        XCTAssertEqual(gesture.selection, [fixture.outer.id])
        XCTAssertEqual(gesture.preview, .marquee(CGRect(x: 110, y: 150, width: 140, height: 150)))
        gesture.drag(to: CGPoint(x: 230, y: 150))
        XCTAssertEqual(gesture.selection, [], "shrinking the marquee drops what it no longer touches")
        XCTAssertNil(gesture.release(at: CGPoint(x: 350, y: 50)))
        XCTAssertEqual(gesture.selection, [fixture.side.id])
    }

    func testShiftMarqueeAddsToTheSelection() {
        let fixture = Fixtures.nestedProject()
        let (gesture, _) = gesture(
            context(fixture, selection: [fixture.inner.id]), from: CGPoint(x: 250, y: 300),
            to: CGPoint(x: 350, y: 50), modifiers: .shift)
        XCTAssertEqual(gesture.selection, [fixture.inner.id, fixture.side.id])
    }

    // MARK: Select tool: resizing

    func testDraggingAHandleResizesWithOnlyTheDraggedEdgesSnapped() throws {
        let fixture = Fixtures.nestedProject()
        fixture.side.frame = Frame(x: 301, y: 3, w: 100, h: 100)
        let (_, command) = gesture(
            context(fixture, selection: [fixture.side.id]), from: CGPoint(x: 401, y: 103),
            to: CGPoint(x: 431, y: 115))
        let resize = try XCTUnwrap(command as? ResizeRegion)
        XCTAssertEqual(resize.frame, Frame(x: 301, y: 3, w: 131, h: 109))
        XCTAssertEqual(try frames(after: resize, on: fixture)[fixture.side.id], resize.frame)
    }

    func testAHandleStopsAtTheMinimumSize() {
        let original = Frame(x: 100, y: 100, w: 50, h: 50)
        XCTAssertEqual(
            CanvasGesture.resizedFrame(original, handle: .left, dx: 200, dy: 0, grid: nil),
            Frame(x: 146, y: 100, w: 4, h: 50))
        XCTAssertEqual(
            CanvasGesture.resizedFrame(original, handle: .topLeft, dx: 80, dy: 300, grid: nil),
            Frame(x: 146, y: 146, w: 4, h: 4))
        XCTAssertEqual(
            CanvasGesture.resizedFrame(original, handle: .bottom, dx: 0, dy: -100, grid: nil),
            Frame(x: 100, y: 100, w: 50, h: 4))
    }

    func testSnappingNeverTakesAResizeBelowTheMinimum() {
        let original = Frame(x: 100, y: 100, w: 51, h: 50)
        // The left edge stops at 147, snaps to 144, and the frame is 7 pt wide.
        XCTAssertEqual(
            CanvasGesture.resizedFrame(original, handle: .left, dx: 200, dy: 0, grid: 8),
            Frame(x: 144, y: 100, w: 7, h: 50))
        // With the right edge at 149, the left edge would snap to 152, so it goes out to 144 instead.
        XCTAssertEqual(
            CanvasGesture.resizedFrame(Frame(x: 100, y: 100, w: 49, h: 50), handle: .left, dx: 200, dy: 0, grid: 8),
            Frame(x: 144, y: 100, w: 5, h: 50))
    }

    func testHandlesAreHitOnlyForASingleSelectionAndScaleWithZoom() {
        let fixture = Fixtures.nestedProject()
        // 8 screen points outside the corner is outside the handle at 100 % but inside it at 25 %.
        let point = CGPoint(x: 408, y: 108)
        let atFull = CanvasGesture(pressAt: point, context: context(fixture, selection: [fixture.side.id]))
        XCTAssertEqual(atFull.selection, [], "a miss clears the selection")
        var zoomedOut = CanvasGesture(
            pressAt: point, context: context(fixture, selection: [fixture.side.id], zoom: 0.25))
        zoomedOut.drag(to: CGPoint(x: 440, y: 140))
        XCTAssertEqual(zoomedOut.preview, .frames([fixture.side.id: Frame(x: 300, y: 0, w: 132, h: 136)]))

        let multiple = CanvasGesture(
            pressAt: CGPoint(x: 400, y: 100), context: context(fixture, selection: [fixture.side.id, fixture.inner.id]))
        XCTAssertEqual(multiple.selection, [fixture.side.id, fixture.inner.id], "a press on the region, not a handle")
    }

    // MARK: Write tool

    func testTheWriteToolSelectsOnClickAndIgnoresDrags() {
        let fixture = Fixtures.nestedProject()
        let click = gesture(context(fixture, tool: .write), from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50))
        XCTAssertEqual(click.0.selection, [fixture.inner.id])
        let empty = gesture(
            context(fixture, tool: .write, selection: [fixture.inner.id]), from: CGPoint(x: 250, y: 400),
            to: CGPoint(x: 250, y: 400))
        XCTAssertEqual(empty.0.selection, [])
        let drag = gesture(context(fixture, tool: .write), from: CGPoint(x: 50, y: 50), to: CGPoint(x: 90, y: 90))
        XCTAssertNil(drag.1)
        XCTAssertEqual(drag.0.selection, [])
    }
}
