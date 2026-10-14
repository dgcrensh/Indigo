import Foundation
import XCTest

@testable import DescriberCore

/// Scroll positions, drawn frames, and parenting and gestures inside scrolled content (milestone 9).
final class ScrollingTests: XCTestCase {
    /// A list scrolling vertically, with a row in view and a row below the fold, and a footer under the list:
    ///
    ///     list    (0, 100, 200 × 200), content 200 × 600
    ///       row1  (10, 110, 180 × 40)
    ///       row2  (10, 400, 180 × 40)   in view when scrolled 300
    ///     footer  (0, 320, 200 × 40)
    ///     badge   (250, 150, 40 × 20)
    private struct ListScreen {
        let project: Project
        let screen: Screen
        let list: Region
        let row1: Region
        let row2: Region
        let footer: Region
        let badge: Region

        init() {
            row1 = Region(id: RegionID("row1"), title: "Row 1", frame: Frame(x: 10, y: 110, w: 180, h: 40))
            row2 = Region(id: RegionID("row2"), title: "Row 2", frame: Frame(x: 10, y: 400, w: 180, h: 40))
            list = Region(
                id: RegionID("list"), title: "List", frame: Frame(x: 0, y: 100, w: 200, h: 200),
                scroll: Scroll(axis: .vertical, contentWidth: 200, contentHeight: 600), children: [row1, row2])
            footer = Region(id: RegionID("footer"), title: "Footer", frame: Frame(x: 0, y: 320, w: 200, h: 40))
            badge = Region(id: RegionID("badge"), title: "Badge", frame: Frame(x: 250, y: 150, w: 40, h: 20))
            screen = Screen(
                id: ScreenID("00000000-0000-4000-8000-000000000001"), name: "Home",
                viewport: Viewport(width: 400, height: 800), regions: [list, footer, badge])
            project = Project(name: "Test", screens: [screen])
        }

        var index: RegionIndex { RegionIndex(screen: screen) }
    }

    private let scrolled = [RegionID("list"): ScrollOffset(x: 0, y: 300)]

    // MARK: Layout

    func testOffsetsClampToTheContentAndTheAxis() {
        let fixture = ListScreen()
        let layout = ScrollLayout(screen: fixture.screen, offsets: [fixture.list.id: ScrollOffset(x: 50, y: 1000)])
        XCTAssertEqual(layout.offset(of: fixture.list.id), ScrollOffset(x: 0, y: 400))
        XCTAssertEqual(ScrollLayout.maximumOffset(of: fixture.list), ScrollOffset(x: 0, y: 400))
        XCTAssertEqual(
            ScrollLayout(screen: fixture.screen, offsets: [fixture.list.id: ScrollOffset(x: 0, y: -20)])
                .offset(of: fixture.list.id), .zero)
        XCTAssertEqual(
            ScrollLayout(screen: fixture.screen, offsets: [fixture.footer.id: ScrollOffset(x: 0, y: 20)])
                .offset(of: fixture.footer.id), .zero, "a region that doesn't scroll has no offset")
        fixture.list.scroll = Scroll(axis: .both, contentWidth: 300, contentHeight: 150)
        XCTAssertEqual(ScrollLayout.maximumOffset(of: fixture.list), ScrollOffset(x: 100, y: 0))
    }

    func testScrolledChildrenAreDrawnMovedAndClipped() {
        let fixture = ListScreen()
        let layout = ScrollLayout(screen: fixture.screen, offsets: scrolled)
        XCTAssertEqual(layout.drawnFrame(of: fixture.list.id), fixture.list.frame)
        XCTAssertNil(layout.clip(of: fixture.list.id))
        XCTAssertEqual(layout.drawnFrame(of: fixture.row2.id), Frame(x: 10, y: 100, w: 180, h: 40))
        XCTAssertEqual(layout.clip(of: fixture.row2.id), fixture.list.frame)
        XCTAssertEqual(layout.visibleFrame(of: fixture.row2.id), Frame(x: 10, y: 100, w: 180, h: 40))
        XCTAssertEqual(layout.drawnFrame(of: fixture.row1.id), Frame(x: 10, y: -190, w: 180, h: 40))
        XCTAssertNil(layout.visibleFrame(of: fixture.row1.id), "scrolled out of view")
        XCTAssertEqual(layout.drawnFrame(of: fixture.footer.id), fixture.footer.frame)
        XCTAssertEqual(layout.drawnContentArea(of: fixture.list.id), Frame(x: 0, y: -200, w: 200, h: 600))

        let unscrolled = ScrollLayout(screen: fixture.screen)
        XCTAssertNil(unscrolled.visibleFrame(of: fixture.row2.id), "below the fold, even with nothing scrolled")
        XCTAssertEqual(unscrolled.drawnFrame(of: fixture.row2.id), fixture.row2.frame)
    }

    func testNestedOffsetsAddUpAndClipsIntersect() {
        let fixture = ListScreen()
        let leaf = Region(id: RegionID("leaf"), title: "Leaf", frame: Frame(x: 20, y: 600, w: 50, h: 20))
        let inner = Region(
            id: RegionID("inner"), title: "Inner", frame: Frame(x: 10, y: 450, w: 180, h: 100),
            scroll: Scroll(axis: .vertical, contentWidth: 180, contentHeight: 300), children: [leaf])
        fixture.list.children.append(inner)
        let layout = ScrollLayout(
            screen: fixture.screen,
            offsets: [fixture.list.id: ScrollOffset(x: 0, y: 300), inner.id: .init(x: 0, y: 100)])
        XCTAssertEqual(layout.drawnFrame(of: inner.id), Frame(x: 10, y: 150, w: 180, h: 100))
        XCTAssertEqual(layout.drawnFrame(of: leaf.id), Frame(x: 20, y: 200, w: 50, h: 20))
        XCTAssertEqual(layout.clip(of: leaf.id), Frame(x: 10, y: 150, w: 180, h: 100))
        XCTAssertEqual(layout.contentShift(of: inner.id), ScrollOffset(x: 0, y: 400))

        let hidden = ScrollLayout(screen: fixture.screen, offsets: [inner.id: .init(x: 0, y: 100)])
        XCTAssertNil(hidden.visibleFrame(of: leaf.id), "the inner list is below the outer list's fold")
    }

    func testHitTestingFindsWhatIsDrawnAndSkipsWhatIsClipped() {
        let fixture = ListScreen()
        let unscrolled = ScrollLayout(screen: fixture.screen)
        XCTAssertNil(unscrolled.region(at: CGPoint(x: 50, y: 410)), "row 2 is there in the file but clipped")
        XCTAssertEqual(unscrolled.region(at: CGPoint(x: 50, y: 120)), fixture.row1.id)
        XCTAssertEqual(unscrolled.region(at: CGPoint(x: 50, y: 330)), fixture.footer.id)
        XCTAssertEqual(unscrolled.regions(touching: CGRect(x: 0, y: 380, width: 300, height: 100)), [])

        let layout = ScrollLayout(screen: fixture.screen, offsets: scrolled)
        XCTAssertEqual(layout.region(at: CGPoint(x: 50, y: 110)), fixture.row2.id)
        XCTAssertEqual(layout.region(at: CGPoint(x: 50, y: 160)), fixture.list.id, "row 1 scrolled away")
        XCTAssertEqual(
            layout.regions(touching: CGRect(x: 0, y: 90, width: 50, height: 20)), [fixture.list.id, fixture.row2.id])
    }

    func testTheScrollTargetIsTheTopmostSelectedScrollableRegionUnderThePoint() {
        let fixture = ListScreen()
        let layout = ScrollLayout(screen: fixture.screen)
        let inList = CGPoint(x: 50, y: 120)
        XCTAssertEqual(layout.scrollTarget(at: inList, among: [fixture.list.id]), fixture.list.id)
        XCTAssertEqual(layout.scrollTarget(at: inList, among: [fixture.row1.id, fixture.list.id]), fixture.list.id)
        XCTAssertNil(layout.scrollTarget(at: inList, among: []), "an unselected region doesn't scroll")
        XCTAssertNil(layout.scrollTarget(at: CGPoint(x: 50, y: 330), among: [fixture.list.id]))
        fixture.list.scroll = Scroll(axis: .vertical, contentWidth: 200, contentHeight: 200)
        XCTAssertNil(
            ScrollLayout(screen: fixture.screen).scrollTarget(at: inList, among: [fixture.list.id]),
            "content no larger than the frame has nothing to scroll")
    }

    func testScrollingClampsAndIndicatorsShowThePosition() throws {
        let fixture = ListScreen()
        let layout = ScrollLayout(screen: fixture.screen, offsets: [fixture.list.id: ScrollOffset(x: 0, y: 200)])
        XCTAssertEqual(layout.scrolled(fixture.list.id, byDX: 30, dy: 150), ScrollOffset(x: 0, y: 350))
        XCTAssertEqual(layout.scrolled(fixture.list.id, byDX: 0, dy: 500), ScrollOffset(x: 0, y: 400))
        XCTAssertEqual(layout.scrolled(fixture.list.id, byDX: 0, dy: -500), .zero)
        XCTAssertNil(layout.scrolled(fixture.footer.id, byDX: 0, dy: 10))

        let indicators = layout.indicators(of: fixture.list.id)
        XCTAssertEqual(indicators.count, 1)
        let indicator = try XCTUnwrap(indicators.first)
        XCTAssertEqual(indicator.axis, .vertical)
        XCTAssertEqual(indicator.start, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(indicator.length, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(layout.indicators(of: fixture.footer.id), [])
    }

    func testAPreviewedRegionIsClippedOnlyByPreviewedScrollingRegions() throws {
        let fixture = ListScreen()
        let layout = ScrollLayout(screen: fixture.screen, offsets: scrolled)
        let dragged = Frame(x: 260, y: 100, w: 180, h: 40)
        let alone = try XCTUnwrap(layout.drawn(fixture.row2.id, previewing: [fixture.row2.id: dragged]))
        XCTAssertEqual(alone.frame, dragged)
        XCTAssertNil(alone.clip, "dragged out of the list, it stays in view")

        let movedList = Frame(x: 50, y: 100, w: 200, h: 200)
        let together = try XCTUnwrap(
            layout.drawn(
                fixture.row1.id,
                previewing: [fixture.list.id: movedList, fixture.row1.id: Frame(x: 60, y: -190, w: 180, h: 40)]))
        XCTAssertEqual(together.clip, movedList)
        XCTAssertEqual(layout.drawn(fixture.footer.id, previewing: [:])?.frame, fixture.footer.frame)
    }

    // MARK: Parenting

    func testDrawingIntoScrolledContentMovesTheFileFrameByTheOffset() throws {
        let fixture = ListScreen()
        let id = RegionID("new")
        try EditSession(project: fixture.project).perform(
            CreateRegion(
                screen: fixture.screen.id, frame: Frame(x: 20, y: 150, w: 50, h: 30), id: id, scrollOffsets: scrolled))
        let index = fixture.index
        XCTAssertEqual(index.parent(of: id)?.id, fixture.list.id)
        XCTAssertEqual(index.region(id)?.frame, Frame(x: 20, y: 450, w: 50, h: 30))
    }

    func testDrawingBelowAnUnscrolledFrameMakesNoChild() throws {
        let fixture = ListScreen()
        let below = RegionID("below")
        let straddling = RegionID("straddling")
        let session = EditSession(project: fixture.project)
        try session.perform(
            CreateRegion(screen: fixture.screen.id, frame: Frame(x: 220, y: 380, w: 50, h: 30), id: below))
        try session.perform(
            CreateRegion(screen: fixture.screen.id, frame: Frame(x: 20, y: 380, w: 50, h: 30), id: RegionID("x")))
        try session.perform(
            CreateRegion(screen: fixture.screen.id, frame: Frame(x: 20, y: 280, w: 50, h: 40), id: straddling))
        let index = fixture.index
        XCTAssertNil(index.parent(of: RegionID("x")), "inside the content area, but not in view")
        XCTAssertEqual(index.region(RegionID("x"))?.frame, Frame(x: 20, y: 380, w: 50, h: 30))
        XCTAssertEqual(index.parent(of: straddling)?.id, fixture.list.id, "overlapping the frame, it is in view")
    }

    func testMovingOutOfScrolledContentLandsWhereItIsDropped() throws {
        let fixture = ListScreen()
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        try session.perform(
            MoveRegions(
                screen: fixture.screen.id, regions: [fixture.row2.id], dx: 250, dy: 0, scrollOffsets: scrolled))
        XCTAssertNil(fixture.index.parent(of: fixture.row2.id))
        XCTAssertEqual(fixture.row2.frame, Frame(x: 260, y: 100, w: 180, h: 40), "where it was drawn, not 300 lower")
        try session.undo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
    }

    func testMovingIntoScrolledContentLandsWhereItIsDropped() throws {
        let fixture = ListScreen()
        try EditSession(project: fixture.project).perform(
            MoveRegions(
                screen: fixture.screen.id, regions: [fixture.badge.id], dx: -200, dy: 0, scrollOffsets: scrolled))
        XCTAssertEqual(fixture.index.parent(of: fixture.badge.id)?.id, fixture.list.id)
        XCTAssertEqual(fixture.badge.frame, Frame(x: 50, y: 450, w: 40, h: 20))
        XCTAssertEqual(
            ScrollLayout(screen: fixture.screen, offsets: scrolled).drawnFrame(of: fixture.badge.id),
            Frame(x: 50, y: 150, w: 40, h: 20))
    }

    func testMovingWithinScrolledContentKeepsTheParent() throws {
        let fixture = ListScreen()
        try EditSession(project: fixture.project).perform(
            MoveRegions(screen: fixture.screen.id, regions: [fixture.row2.id], dx: 0, dy: 20, scrollOffsets: scrolled))
        XCTAssertEqual(fixture.index.parent(of: fixture.row2.id)?.id, fixture.list.id)
        XCTAssertEqual(fixture.row2.frame, Frame(x: 10, y: 420, w: 180, h: 40))
    }

    func testNudgingAHiddenRegionKeepsItsParent() throws {
        let fixture = ListScreen()
        try EditSession(project: fixture.project).perform(
            MoveRegions(screen: fixture.screen.id, regions: [fixture.row2.id], dx: 0, dy: 8))
        XCTAssertEqual(fixture.index.parent(of: fixture.row2.id)?.id, fixture.list.id)
        XCTAssertEqual(fixture.row2.frame, Frame(x: 10, y: 408, w: 180, h: 40))
    }

    func testResizingInScrolledContentResizesWhereItIsDrawn() throws {
        let fixture = ListScreen()
        try EditSession(project: fixture.project).perform(
            ResizeRegion(
                screen: fixture.screen.id, region: fixture.row2.id, frame: Frame(x: 10, y: 100, w: 180, h: 60),
                scrollOffsets: scrolled))
        XCTAssertEqual(fixture.row2.frame, Frame(x: 10, y: 400, w: 180, h: 60))
        XCTAssertEqual(fixture.index.parent(of: fixture.row2.id)?.id, fixture.list.id)
    }

    func testDuplicatingInScrolledContentPastesBesideTheOriginal() throws {
        let fixture = ListScreen()
        let clipboard = try XCTUnwrap(RegionClipboard(copying: [fixture.row2.id], on: fixture.screen))
        let paste = clipboard.paste(
            onto: fixture.screen, in: fixture.project, grid: 8, actionName: "Duplicate", scrollOffsets: scrolled)
        try EditSession(project: fixture.project).perform(paste)
        let copy = try XCTUnwrap(paste.pasted.first)
        XCTAssertEqual(fixture.index.parent(of: copy.id)?.id, fixture.list.id)
        XCTAssertEqual(copy.frame, Frame(x: 18, y: 408, w: 180, h: 40))
    }

    // MARK: Changing scrolling

    func testTurningScrollingOffReplacesChildrenOutsideTheFrame() throws {
        let fixture = ListScreen()
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        try session.perform(RegionCommands.setScroll(nil, of: fixture.list.id))
        XCTAssertEqual(session.undoActionName, "Change Scrolling")
        XCTAssertNil(fixture.list.scroll)
        XCTAssertNil(fixture.index.parent(of: fixture.row2.id), "row 2 is below the frame")
        XCTAssertEqual(fixture.index.parent(of: fixture.row1.id)?.id, fixture.list.id)
        let applied = Fixtures.bytes(fixture.project)
        try session.undo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
        try session.redo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), applied)
    }

    func testADetailsSessionThatChangesScrollingUndoesToTheSameBytes() throws {
        let fixture = ListScreen()
        let session = EditSession(project: fixture.project)
        let before = Fixtures.bytes(fixture.project)
        let editor = try RegionEditor(region: fixture.list.id, in: session)
        try editor.setTitle("Rows")
        try editor.setScroll(nil)
        XCTAssertNil(fixture.index.parent(of: fixture.row2.id))
        XCTAssertEqual(editor.commit(), .recorded(actionName: "Edit Region"))
        let applied = Fixtures.bytes(fixture.project)
        try session.undo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), before)
        try session.redo()
        XCTAssertEqual(Fixtures.bytes(fixture.project), applied)

        let cancelled = try RegionEditor(region: fixture.list.id, in: session)
        try cancelled.setScroll(Scroll(axis: .vertical, contentWidth: 200, contentHeight: 600))
        cancelled.cancel()
        XCTAssertEqual(Fixtures.bytes(fixture.project), applied)
    }

    // MARK: Gestures

    private func context(_ fixture: ListScreen, tool: Tool = .select, selection: [RegionID] = []) -> GestureContext {
        GestureContext(
            screen: fixture.screen, tool: tool, selection: selection, snappingEnabled: false, scrollOffsets: scrolled)
    }

    func testAMoveInScrolledContentPreviewsAndCommitsAtDrawnFrames() throws {
        let fixture = ListScreen()
        var gesture = CanvasGesture(pressAt: CGPoint(x: 50, y: 120), context: context(fixture))
        XCTAssertEqual(gesture.selection, [fixture.row2.id])
        gesture.drag(to: CGPoint(x: 50, y: 140))
        XCTAssertEqual(gesture.preview, .frames([fixture.row2.id: Frame(x: 10, y: 120, w: 180, h: 40)]))
        let command = try XCTUnwrap(gesture.release(at: CGPoint(x: 50, y: 140)))
        try EditSession(project: fixture.project).perform(command)
        XCTAssertEqual(fixture.row2.frame, Frame(x: 10, y: 420, w: 180, h: 40))
    }

    func testAResizeInScrolledContentGrabsTheDrawnHandle() throws {
        let fixture = ListScreen()
        var gesture = CanvasGesture(
            pressAt: CGPoint(x: 190, y: 140), context: context(fixture, selection: [fixture.row2.id]))
        gesture.drag(to: CGPoint(x: 190, y: 160))
        XCTAssertEqual(gesture.preview, .frames([fixture.row2.id: Frame(x: 10, y: 100, w: 180, h: 60)]))
        let command = try XCTUnwrap(gesture.release(at: CGPoint(x: 190, y: 160)))
        try EditSession(project: fixture.project).perform(command)
        XCTAssertEqual(fixture.row2.frame, Frame(x: 10, y: 400, w: 180, h: 60))
    }

    func testClickingWhereContentIsClippedAwayHitsNothingThere() {
        let fixture = ListScreen()
        var gesture = CanvasGesture(
            pressAt: CGPoint(x: 50, y: 410), context: GestureContext(screen: fixture.screen, tool: .select))
        _ = gesture.release(at: CGPoint(x: 50, y: 410))
        XCTAssertEqual(gesture.selection, [], "row 2 is below the fold")
    }

    func testDrawingInScrolledContentMakesAChildThere() throws {
        let fixture = ListScreen()
        var gesture = CanvasGesture(pressAt: CGPoint(x: 20, y: 150), context: context(fixture, tool: .region))
        let command = try XCTUnwrap(gesture.release(at: CGPoint(x: 70, y: 180)))
        try EditSession(project: fixture.project).perform(command)
        let region = try XCTUnwrap(fixture.index.region(gesture.newRegionID))
        XCTAssertEqual(region.frame, Frame(x: 20, y: 450, w: 50, h: 30))
        XCTAssertEqual(fixture.index.parent(of: region.id)?.id, fixture.list.id)
    }
}
