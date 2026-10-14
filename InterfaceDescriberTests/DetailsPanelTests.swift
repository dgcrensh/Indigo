import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// The details panel, driven the way its fields and the canvas drive it. The window is off screen, so nothing
/// animates.
final class DetailsPanelTests: XCTestCase {
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        return (document, controller, controller.canvasController)
    }

    /// Runs `action` in its own undo group, as one event is.
    @MainActor
    private func event(_ document: Document, _ action: () throws -> Void) rethrows {
        document.undoManager?.beginUndoGrouping()
        defer { document.undoManager?.endUndoGrouping() }
        try action()
    }

    @MainActor
    private func click(
        _ canvas: CanvasViewController, at point: CGPoint, clickCount: Int = 1, in document: Document
    ) {
        event(document) {
            canvas.canvasPressed(at: point, modifiers: [], clickCount: clickCount)
            canvas.canvasReleased(at: point, optionHeld: false)
        }
        canvas.update()
    }

    @MainActor
    private func draw(_ canvas: CanvasViewController, from start: CGPoint, to end: CGPoint, in document: Document) {
        canvas.choose(.region)
        event(document) {
            canvas.canvasPressed(at: start, modifiers: [])
            canvas.canvasDragged(to: end, optionHeld: false)
            canvas.canvasReleased(at: end, optionHeld: false)
        }
        canvas.update()
    }

    @MainActor
    private func addRegion(_ frame: Frame, titled title: String, to document: Document) throws -> Region {
        let screen = try XCTUnwrap(document.model.activeScreen)
        let command = CreateRegion(screen: screen.id, frame: frame, title: title)
        try event(document) { try document.perform(command) }
        return try XCTUnwrap(document.model.project.region(withID: command.id)?.region)
    }

    @MainActor
    private func type(_ text: String, into field: NSTextField, of panel: DetailsPanelController) {
        field.stringValue = text
        panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @MainActor
    private func pressEscape(in panel: DetailsPanelController, of document: Document) {
        event(document) {
            _ = panel.control(
                panel.titleField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        }
    }

    @MainActor
    private func isEditing(_ field: NSTextField, in window: NSWindow?) -> Bool {
        (window?.firstResponder as? NSTextView)?.delegate === field
    }

    // MARK: Opening and closing

    @MainActor
    func testDrawingOpensThePanelWithTheTitleFocusedAndFitsTheRegion() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let before = canvas.canvasView.camera

        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        let region = try XCTUnwrap(document.model.activeScreen?.regions.first)
        XCTAssertTrue(controller.isShowingDetails)
        XCTAssertTrue(isEditing(panel.titleField, in: controller.window), "the title has focus")
        let fitted = Camera.fitting(
            region.frame.cgRect, viewSize: canvas.canvasView.bounds.size, padding: CanvasViewController.fitPadding,
            maximumZoom: CanvasViewController.detailsMaximumZoom)
        XCTAssertEqual(canvas.canvasView.camera, fitted)

        pressEscape(in: panel, of: document)
        XCTAssertFalse(controller.isShowingDetails)
        XCTAssertNil(document.model.details)
        XCTAssertEqual(canvas.canvasView.camera, before, "the canvas goes back")
        canvas.update()
        XCTAssertEqual(document.model.activeScreen?.regions.count, 0, "a new region with a blank title is discarded")
        XCTAssertEqual(document.model.session.undoDepth, 0)
    }

    @MainActor
    func testATitledNewRegionIsOneUndoStep() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        let region = try XCTUnwrap(document.model.activeScreen?.regions.first)

        type("Avatar", into: panel.titleField, of: panel)
        XCTAssertEqual(region.title, "Avatar", "the canvas shows the title while it is typed")
        pressEscape(in: panel, of: document)
        XCTAssertEqual(document.model.session.undoDepth, 1)
        XCTAssertEqual(document.undoManager?.undoActionName, "New Region")

        document.undoManager?.undo()
        XCTAssertEqual(document.model.activeScreen?.regions.count, 0)
        document.undoManager?.redo()
        XCTAssertEqual(document.model.activeScreen?.regions.first?.title, "Avatar")
    }

    @MainActor
    func testClearingAnExistingTitleRevertsIt() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        canvas.update()

        canvas.choose(.write)
        click(canvas, at: CGPoint(x: 30, y: 30), in: document)
        XCTAssertEqual(document.model.details?.region, region.id)
        XCTAssertEqual(panel.titleField.stringValue, "Box")
        type("", into: panel.titleField, of: panel)
        pressEscape(in: panel, of: document)
        XCTAssertEqual(region.title, "Box")
        XCTAssertEqual(document.model.session.undoDepth, 1, "nothing changed, so no step")
    }

    @MainActor
    func testTheWriteToolSwitchesRegionsAndClosesOnEmptyCanvas() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let first = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "First", to: document)
        let second = try addRegion(Frame(x: 16, y: 200, w: 80, h: 40), titled: "Second", to: document)
        canvas.update()

        canvas.choose(.write)
        click(canvas, at: CGPoint(x: 30, y: 30), in: document)
        panel.descriptionView.string = "Top."
        panel.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.descriptionView))
        click(canvas, at: CGPoint(x: 30, y: 210), in: document)
        XCTAssertEqual(document.model.details?.region, second.id)
        XCTAssertEqual(document.model.selection, [second.id])
        XCTAssertEqual(first.title, "First")
        XCTAssertEqual(panel.titleField.stringValue, "Second")
        XCTAssertEqual(first.description, "Top.")
        XCTAssertEqual(document.undoManager?.undoActionName, "Edit Description", "switching commits")
        XCTAssertTrue(controller.isShowingDetails)

        click(canvas, at: CGPoint(x: 300, y: 600), in: document)
        XCTAssertNil(document.model.details)
        XCTAssertFalse(controller.isShowingDetails)
    }

    @MainActor
    func testASelectToolDoubleClickOpensTheRegion() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        canvas.update()
        click(canvas, at: CGPoint(x: 30, y: 30), in: document)
        XCTAssertNil(document.model.details, "a single click only selects")
        click(canvas, at: CGPoint(x: 30, y: 30), clickCount: 2, in: document)
        XCTAssertEqual(document.model.details?.region, region.id)
        XCTAssertTrue(controller.isShowingDetails)
    }

    // MARK: Keys

    @MainActor
    func testReturnAndTabMoveBetweenFields() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let window = try XCTUnwrap(controller.window)
        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)

        XCTAssertTrue(
            panel.control(
                panel.titleField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertIdentical(window.firstResponder, panel.descriptionView, "Return in the title moves to the description")
        XCTAssertFalse(
            panel.textView(panel.descriptionView, doCommandBy: #selector(NSResponder.insertNewline(_:))),
            "Return in the description inserts a line")
        XCTAssertTrue(panel.textView(panel.descriptionView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertNotIdentical(window.firstResponder, panel.descriptionView, "Tab moves on")
    }

    @MainActor
    func testToolKeysAreOffWhileTheTitleIsEdited() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        XCTAssertTrue(controller.isEditingText)
        let tools = try XCTUnwrap(MainMenu.make().items.first { $0.title == "Tools" }?.submenu)
        let regionTool = try XCTUnwrap(tools.items.first { $0.title == "Region Tool" })
        XCTAssertFalse(controller.validateMenuItem(regionTool))
        XCTAssertNil(document.model.keybinds.action(for: KeyCombo("r"), isEditingText: controller.isEditingText))
    }

    @MainActor
    func testTypingUndoStaysInThePanel() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(controller.detailsController.isEditingText(window.firstResponder))
        let panel = controller.detailsController
        XCTAssertIdentical(window.firstResponder, panel.fieldEditor)
        XCTAssertIdentical(window.firstResponder?.undoManager, panel.textUndoManager)
        XCTAssertIdentical(panel.descriptionView.undoManager, panel.textUndoManager)
        window.makeFirstResponder(canvas.canvasView)
        XCTAssertIdentical(window.firstResponder?.undoManager, document.undoManager)
    }

    // MARK: Fields

    @MainActor
    func testKindLinksAndScrollingAreOneEditRegionStep() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        try event(document) {
            try document.perform(AddScreen(name: "Settings", viewport: .defaultForNewScreens))
        }
        let settings = try XCTUnwrap(document.model.project.screens.last)
        canvas.update()
        canvas.choose(.write)
        click(canvas, at: CGPoint(x: 30, y: 30), in: document)

        panel.kindChips.choose(.button)
        panel.addLink(nil)
        XCTAssertEqual(panel.linkRows.count, 1)
        type("click", into: panel.linkRows[0].triggerField, of: panel)
        panel.scrollsCheckbox.state = .on
        panel.scrollsChanged(nil)
        XCTAssertFalse(panel.contentHeightField.isHidden)
        panel.contentHeightField.stringValue = "10"
        pressEscape(in: panel, of: document)

        XCTAssertEqual(region.kind, .button)
        XCTAssertEqual(region.links, [Link(screen: settings.id, trigger: "click")])
        XCTAssertEqual(
            region.scroll, Scroll(axis: .vertical, contentWidth: 80, contentHeight: 40),
            "a content height typed before Escape applies, raised to the frame's height")
        XCTAssertEqual(document.undoManager?.undoActionName, "Edit Region")
        let depth = document.model.session.undoDepth
        document.undoManager?.undo()
        XCTAssertEqual(document.model.session.undoDepth, depth - 1)
        XCTAssertEqual(RegionFields(region), RegionFields(title: "Box"))
    }

    @MainActor
    func testUndoWhileThePanelIsOpenRevertsTheSessionAndClosesIt() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let first = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "First", to: document)
        _ = try addRegion(Frame(x: 16, y: 200, w: 80, h: 40), titled: "Second", to: document)
        canvas.update()
        // Opened directly: an empty undo group from a click would sit on top of the undo stack.
        try document.model.openDetails(for: first.id)
        type("Changed", into: panel.titleField, of: panel)

        document.undoManager?.undo()
        XCTAssertNil(document.model.details)
        XCTAssertFalse(controller.isShowingDetails)
        XCTAssertEqual(first.title, "First", "the open session is put back")
        XCTAssertEqual(document.model.activeScreen?.regions.count, 1, "then the last step is undone")
    }
    // MARK: Kind chips (milestone 13)

    @MainActor
    private func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws
        -> NSEvent
    {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    @MainActor
    func testClickingAChipSetsTheKindAsOneUndoStep() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let window = try XCTUnwrap(controller.window)
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        canvas.update()
        try document.model.openDetails(for: region.id)
        window.layoutIfNeeded()
        XCTAssertEqual(panel.kindChips.selectedKind, .open)

        let chips = panel.kindChips
        let frame = try XCTUnwrap(chips.chipFrame(for: .image))
        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: chips.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        let depth = document.model.session.undoDepth
        chips.mouseDown(with: click)
        XCTAssertEqual(region.kind, .image, "the canvas shows the kind while the panel is open")
        XCTAssertEqual(chips.selectedKind, .image)
        pressEscape(in: panel, of: document)
        XCTAssertEqual(document.model.session.undoDepth, depth + 1)
        XCTAssertEqual(document.undoManager?.undoActionName, "Change Kind")
        document.undoManager?.undo()
        XCTAssertEqual(region.kind, .open)
    }

    @MainActor
    func testArrowsAndSpaceMoveWithinTheChipsAndNeverNudge() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let window = try XCTUnwrap(controller.window)
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        canvas.update()
        document.model.selection = [region.id]
        try document.model.openDetails(for: region.id)
        let chips = panel.kindChips
        XCTAssertTrue(window.makeFirstResponder(chips))
        XCTAssertEqual(chips.focusedKind, .open)

        chips.keyDown(with: try keyEvent(String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), keyCode: 124))
        XCTAssertEqual(chips.focusedKind, .container)
        XCTAssertEqual(region.kind, .open, "moving doesn't choose")
        XCTAssertEqual(region.frame, Frame(x: 16, y: 16, w: 80, h: 40), "Right doesn't nudge the region")
        XCTAssertIdentical(window.firstResponder, chips)
        let nudge = NSMenuItem(
            title: "Nudge Right", action: #selector(DocumentWindowController.nudge(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(nudge), "the canvas's arrow keys are off while the chips have focus")

        chips.keyDown(with: try keyEvent(" ", keyCode: 49))
        XCTAssertEqual(region.kind, .container)
        XCTAssertEqual(chips.selectedKind, .container)
    }

    @MainActor
    func testTheChipsAreOneTabStopBetweenTheDescriptionAndTheLinks() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let window = try XCTUnwrap(controller.window)
        let region = try addRegion(Frame(x: 16, y: 16, w: 80, h: 40), titled: "Box", to: document)
        canvas.update()
        try document.model.openDetails(for: region.id)
        panel.addLink(nil)
        window.makeFirstResponder(panel.descriptionView)

        XCTAssertTrue(panel.textView(panel.descriptionView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertIdentical(window.firstResponder, panel.kindChips, "Tab from the description lands on the chips")
        panel.kindChips.keyDown(with: try keyEvent("\t", keyCode: 48))
        let responder = try XCTUnwrap(window.firstResponder as? NSView)
        let row = try XCTUnwrap(panel.linkRows.first)
        let editedField = (responder as? NSTextView)?.delegate as? NSView
        XCTAssertTrue(
            responder.isDescendant(of: row) || editedField?.isDescendant(of: row) == true,
            "Tab again lands on the links, not \(responder)")
    }

    @MainActor
    func testTheFocusedFieldsWellShowsTheRing() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let panel = controller.detailsController
        let window = try XCTUnwrap(controller.window)
        draw(canvas, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 75), in: document)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertIdentical(panel.focusedWell, panel.titleWell)
        window.makeFirstResponder(panel.descriptionView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertIdentical(panel.focusedWell, panel.descriptionWell)
    }
}
