import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// Tools, gestures, toasts and the grid size, driven through the canvas controller the way the canvas view's mouse
/// and key events drive it.
final class CanvasToolTests: XCTestCase {
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        return (document, controller, controller.canvasController)
    }

    /// One press, drag and release in its own undo group, as one mouse gesture is.
    @MainActor
    private func drag(
        _ canvas: CanvasViewController, from start: CGPoint, to end: CGPoint, in document: Document,
        modifiers: KeyCombo.Modifiers = []
    ) {
        document.undoManager?.beginUndoGrouping()
        canvas.canvasPressed(at: start, modifiers: modifiers)
        canvas.canvasDragged(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), optionHeld: false)
        canvas.canvasDragged(to: end, optionHeld: false)
        canvas.canvasReleased(at: end, optionHeld: false)
        document.undoManager?.endUndoGrouping()
        canvas.update()
    }

    @MainActor
    func testDrawingMovingAndResizingAreOneUndoStepEach() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let undoManager = try XCTUnwrap(document.undoManager)
        let screen = try XCTUnwrap(document.model.activeScreen)

        canvas.choose(.region)
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        let region = try XCTUnwrap(screen.regions.first)
        XCTAssertEqual(region.frame, Frame(x: 24, y: 24, w: 80, h: 48))
        XCTAssertEqual(region.title, "Region")
        XCTAssertEqual(document.model.selection, [region.id])
        XCTAssertEqual(document.model.session.undoDepth, 1)
        XCTAssertEqual(undoManager.undoActionName, "New Region")

        canvas.choose(.select)
        drag(canvas, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 70, y: 60), in: document)
        XCTAssertEqual(region.frame, Frame(x: 48, y: 48, w: 80, h: 48))
        XCTAssertEqual(document.model.session.undoDepth, 2)
        XCTAssertEqual(undoManager.undoActionName, "Move Region")

        drag(canvas, from: CGPoint(x: 128, y: 96), to: CGPoint(x: 160, y: 120), in: document)
        XCTAssertEqual(region.frame, Frame(x: 48, y: 48, w: 112, h: 72))
        XCTAssertEqual(document.model.session.undoDepth, 3)
        XCTAssertEqual(undoManager.undoActionName, "Resize Region")

        undoManager.undo()
        XCTAssertEqual(region.frame, Frame(x: 48, y: 48, w: 80, h: 48))
        undoManager.undo()
        XCTAssertEqual(region.frame, Frame(x: 24, y: 24, w: 80, h: 48))
        undoManager.undo()
        XCTAssertTrue(screen.regions.isEmpty)
        canvas.update()
        XCTAssertEqual(document.model.selection, [], "the undone region leaves the selection")
    }

    @MainActor
    func testTheCanvasShowsTheSelectionAndHandles() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        canvas.choose(.region)
        drag(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        let region = try XCTUnwrap(document.model.activeScreen?.regions.first)
        XCTAssertEqual(canvas.canvasView.selectedLayerIDs, [region.id])
        XCTAssertFalse(canvas.canvasView.showsHandles, "handles show with the Select tool only")
        canvas.choose(.select)
        XCTAssertTrue(canvas.canvasView.showsHandles)
    }

    @MainActor
    func testAMarqueeSelectsTheRegionsItTouches() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let screen = try XCTUnwrap(document.model.activeScreen)
        let frames = [Frame(x: 16, y: 16, w: 80, h: 40), Frame(x: 16, y: 200, w: 80, h: 40)]
        for frame in frames {
            document.undoManager?.beginUndoGrouping()
            try document.perform(CreateRegion(screen: screen.id, frame: frame, title: "Box"))
            document.undoManager?.endUndoGrouping()
        }
        canvas.update()

        drag(canvas, from: CGPoint(x: 300, y: 100), to: CGPoint(x: 50, y: 30), in: document)
        XCTAssertEqual(document.model.selection, [screen.regions[0].id])
        drag(canvas, from: CGPoint(x: 300, y: 100), to: CGPoint(x: 50, y: 220), in: document, modifiers: .shift)
        XCTAssertEqual(document.model.selection, [screen.regions[0].id, screen.regions[1].id])
        XCTAssertEqual(document.model.session.undoDepth, 2, "selecting is not an edit")
    }

    @MainActor
    func testPressingRInTheCanvasPicksTheRegionToolWithAToast() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        canvas.canvasView.keyDown(with: event)
        XCTAssertEqual(document.model.tool, .region)
        XCTAssertEqual(canvas.toastView.text, "Region tool — R")
    }

    @MainActor
    func testSnappingTogglesWithAToastAndHidesTheGrid() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        XCTAssertEqual(canvas.canvasView.gridSize, Snapping.defaultGridSize)
        canvas.toggleSnapping()
        XCTAssertFalse(document.model.snappingEnabled)
        XCTAssertEqual(canvas.toastView.text, "Snapping off — S")
        XCTAssertNil(canvas.canvasView.gridSize)

        canvas.toggleGridSizePopover()
        XCTAssertTrue(canvas.isShowingGridSizePopover)
        XCTAssertEqual(canvas.canvasView.gridSize, Snapping.defaultGridSize, "the grid shows while adjusting it")
        canvas.toggleGridSizePopover()
        XCTAssertFalse(canvas.isShowingGridSizePopover)
        XCTAssertNil(canvas.canvasView.gridSize)
    }

    @MainActor
    func testChangingTheGridSizeMovesNoRegionAndIsSaved() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let screen = try XCTUnwrap(document.model.activeScreen)
        document.undoManager?.beginUndoGrouping()
        try document.perform(CreateRegion(screen: screen.id, frame: Frame(x: 13, y: 13, w: 50, h: 30), title: "Box"))
        document.undoManager?.endUndoGrouping()
        canvas.update()
        let camera = canvas.canvasView.camera

        canvas.setGridSize(16)
        XCTAssertEqual(screen.regions.first?.frame, Frame(x: 13, y: 13, w: 50, h: 30))
        XCTAssertEqual(document.model.project.editorState.screens[screen.id]?.gridSize, 16)
        XCTAssertEqual(canvas.canvasView.gridSize, 16)
        XCTAssertEqual(canvas.canvasView.camera, camera, "the fitted camera is kept")
        XCTAssertEqual(canvas.toastView.text, "Grid 16 pt")
        XCTAssertEqual(document.model.session.undoDepth, 1, "the grid size is not an edit")
    }
}
