import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// Scrolling inside a region on the canvas, and a screen's scrolling in the sidebar (milestone 9).
final class ScrollingTests: XCTestCase {
    private let listID = RegionID("list")
    private let rowID = RegionID("row")

    /// A window on a new document whose screen has a list scrolling vertically, with a row below the fold:
    ///
    ///     list   (0, 100, 200 × 200), content 200 × 600
    ///       row  (10, 400, 180 × 40)
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, CanvasViewController, Screen) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        let screen = try XCTUnwrap(document.model.activeScreen)
        let row = Region(id: rowID, title: "Row", frame: Frame(x: 10, y: 400, w: 180, h: 40))
        screen.regions = [
            Region(
                id: listID, title: "List", frame: Frame(x: 0, y: 100, w: 200, h: 200),
                scroll: Scroll(axis: .vertical, contentWidth: 200, contentHeight: 600), children: [row])
        ]
        document.model.noteChange()
        document.model.snappingEnabled = false
        let canvas = controller.canvasController
        canvas.update()
        canvas.canvasView.camera = Camera(zoom: 1)
        return (document, controller, canvas, screen)
    }

    @MainActor
    private func offsets(_ document: Document, _ screen: Screen) -> [RegionID: ScrollOffset] {
        document.model.project.editorState.screens[screen.id]?.scrollOffsets ?? [:]
    }

    @MainActor
    func testScrollingOverASelectedScrollableRegionScrollsItAndNotTheCamera() throws {
        let (document, controller, canvas, screen) = try makeWindow()
        defer { controller.close() }
        let view = canvas.canvasView
        XCTAssertTrue(view.isClippedAway(rowID), "the row starts below the fold")
        XCTAssertEqual(view.scrollIndicatorCount(of: listID), 1)

        document.model.selection = [listID]
        canvas.update()
        XCTAssertTrue(view.showsContentOutline)
        let camera = view.camera
        view.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: -300)
        XCTAssertEqual(view.camera, camera, "the canvas doesn't pan")
        XCTAssertEqual(offsets(document, screen), [listID: ScrollOffset(x: 0, y: 300)])
        XCTAssertEqual(view.drawnFrame(of: rowID), Frame(x: 10, y: 100, w: 180, h: 40))
        XCTAssertFalse(view.isClippedAway(rowID))
        XCTAssertEqual(document.model.session.undoDepth, 0, "scrolling isn't an edit")

        view.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: -1000)
        XCTAssertEqual(offsets(document, screen), [listID: ScrollOffset(x: 0, y: 400)], "it stops at the end")
        view.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: 1000)
        XCTAssertEqual(offsets(document, screen), [:], "back at the top, no offset is kept")
    }

    @MainActor
    func testScrollingOverAnUnselectedRegionPans() throws {
        let (document, controller, canvas, screen) = try makeWindow()
        defer { controller.close() }
        let view = canvas.canvasView
        let camera = view.camera
        view.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: -100)
        XCTAssertNotEqual(view.camera, camera)
        XCTAssertEqual(offsets(document, screen), [:])
    }

    @MainActor
    func testDrawingAfterScrollingPlacesAChildInTheHiddenContent() throws {
        let (document, controller, canvas, screen) = try makeWindow()
        defer { controller.close() }
        document.model.selection = [listID]
        canvas.update()
        canvas.canvasView.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: -300)

        canvas.choose(.region)
        document.undoManager?.beginUndoGrouping()
        canvas.canvasPressed(at: CGPoint(x: 20, y: 150), modifiers: [])
        canvas.canvasDragged(to: CGPoint(x: 70, y: 180), optionHeld: false)
        canvas.canvasReleased(at: CGPoint(x: 70, y: 180), optionHeld: false)
        document.undoManager?.endUndoGrouping()
        canvas.update()

        let id = try XCTUnwrap(document.model.details?.region)
        let index = RegionIndex(screen: screen)
        XCTAssertEqual(index.parent(of: id)?.id, listID)
        XCTAssertEqual(index.region(id)?.frame, Frame(x: 20, y: 450, w: 50, h: 30))
        XCTAssertEqual(canvas.canvasView.drawnFrame(of: id), Frame(x: 20, y: 150, w: 50, h: 30))
    }

    @MainActor
    func testScrollPositionsAreKeptInTheEditorState() throws {
        let (document, controller, canvas, screen) = try makeWindow()
        defer { controller.close() }
        document.model.selection = [listID]
        canvas.update()
        canvas.canvasView.simulateScroll(at: CGPoint(x: 50, y: 150), dx: 0, dy: -120)
        let tree = ProjectPackage.write(project: document.model.project).tree
        let reread = try ProjectPackage.read(tree)
        XCTAssertEqual(
            reread.editorState.screens[screen.id]?.scrollOffsets, [listID: ScrollOffset(x: 0, y: 120)])
    }

    @MainActor
    func testAScreensScrollingIsSetInOneStep() throws {
        let (document, controller, _, screen) = try makeWindow()
        defer { controller.close() }
        let undoManager = try XCTUnwrap(document.undoManager)
        let screens = controller.screenController
        let viewport = screen.viewport

        undoManager.beginUndoGrouping()
        screens.setScrolls(true, of: screen.id)
        undoManager.endUndoGrouping()
        XCTAssertEqual(
            screen.scroll,
            Scroll(axis: .vertical, contentWidth: viewport.width, contentHeight: viewport.height * 2))
        XCTAssertEqual(undoManager.undoActionName, "Change Scrolling")

        undoManager.beginUndoGrouping()
        screens.setScroll(height: 10, of: screen.id)
        undoManager.endUndoGrouping()
        XCTAssertEqual(screen.scroll?.contentHeight, viewport.height, "content is never shorter than the viewport")

        undoManager.undo()
        undoManager.undo()
        XCTAssertNil(screen.scroll)
    }
}
