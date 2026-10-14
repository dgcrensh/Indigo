import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// The Paper look on the canvas, the tool pill and the details card (milestone 13).
final class PaperLookTests: XCTestCase {
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        return (document, controller, controller.canvasController)
    }

    @MainActor
    private func addRegion(
        _ frame: Frame, titled title: String, kind: RegionKind = .open, to document: Document
    ) throws -> RegionID {
        let screen = try XCTUnwrap(document.model.activeScreen)
        let command = CreateRegion(screen: screen.id, frame: frame, title: title)
        document.undoManager?.beginUndoGrouping()
        try document.perform(command)
        if kind != .open {
            try document.model.openDetails(for: command.id)
            try document.model.editDetails { try $0.setKind(kind) }
            document.model.closeDetails()
        }
        document.undoManager?.endUndoGrouping()
        return command.id
    }

    @MainActor
    private func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws
        -> NSEvent
    {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    // MARK: Canvas

    @MainActor
    func testRegionsDrawInTheirFamilyAndFollowTheAppearance() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let button = try addRegion(Frame(x: 16, y: 16, w: 120, h: 40), titled: "Go", kind: .button, to: document)
        let text = try addRegion(Frame(x: 16, y: 80, w: 120, h: 40), titled: "Body", kind: .text, to: document)
        let tiny = try addRegion(Frame(x: 16, y: 140, w: 4, h: 20), titled: "Rule", to: document)
        canvas.update()
        canvas.canvasView.camera = Camera(zoom: 1)
        let view = canvas.canvasView

        for (name, palette) in [(NSAppearance.Name.aqua, PaperPalette.light), (.darkAqua, PaperPalette.dark)] {
            controller.window?.appearance = NSAppearance(named: name)
            XCTAssertEqual(
                view.fillColor(of: button), palette.colors(for: .action).fill.cgColor, "\(name.rawValue) button")
            XCTAssertNil(view.fillColor(of: text), "a text region has no fill, \(name.rawValue)")
        }
        XCTAssertEqual(view.cornerRadius(of: button), 6)
        XCTAssertEqual(view.cornerRadius(of: tiny), 1, "a small region's corners are capped")
        canvas.canvasView.camera = Camera(zoom: 2)
        XCTAssertEqual(view.cornerRadius(of: button), 12, "corners scale with zoom")
    }

    @MainActor
    func testThePhoneSheetIsRoundedAndHandlesAreCircles() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        XCTAssertEqual(document.model.activeScreen?.viewport.preset, "iphone-15")
        canvas.canvasView.camera = Camera(zoom: 1)
        XCTAssertEqual(canvas.canvasView.sheetCornerRadius, 55)
        canvas.canvasView.camera = Camera(zoom: 0.5)
        XCTAssertEqual(canvas.canvasView.sheetCornerRadius, 27.5)

        let region = try addRegion(Frame(x: 16, y: 16, w: 120, h: 40), titled: "Box", to: document)
        canvas.update()
        document.model.selection = [region]
        canvas.update()
        XCTAssertTrue(canvas.canvasView.showsHandles)
        XCTAssertEqual(canvas.canvasView.handleCornerRadius, CanvasView.handleSize / 2)
    }

    @MainActor
    func testTheGridShowsDotsWhenItShowedLines() throws {
        let (_, controller, canvas) = try makeWindow()
        defer { controller.close() }
        XCTAssertTrue(canvas.canvasView.showsGridDots, "snapping is on")
        canvas.toggleSnapping()
        XCTAssertFalse(canvas.canvasView.showsGridDots)
        canvas.toggleGridSizePopover()
        XCTAssertTrue(canvas.canvasView.showsGridDots, "the grid shows while its size is being changed")
        canvas.toggleGridSizePopover()
        XCTAssertFalse(canvas.canvasView.showsGridDots)
    }

    // MARK: Tool pill

    @MainActor
    func testThePillSwitchesToolsAndFollowsKeys() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let pill = canvas.toolPill
        XCTAssertEqual(pill.toolButtons[.select]?.isAccentFilled, true)

        try XCTUnwrap(pill.toolButtons[.region]).performClick(nil)
        XCTAssertEqual(document.model.tool, .region)
        XCTAssertEqual(canvas.toastView.text, "Region tool — R")
        XCTAssertEqual(pill.toolButtons[.region]?.isAccentFilled, true)
        XCTAssertEqual(pill.toolButtons[.select]?.isAccentFilled, false)

        canvas.canvasView.keyDown(with: try keyEvent("w", keyCode: 13))
        XCTAssertEqual(document.model.tool, .write)
        XCTAssertEqual(pill.toolButtons[.write]?.isAccentFilled, true, "the pill follows a key")
    }

    @MainActor
    func testTheSnapButtonTogglesSnappingAndOptionOpensTheGridSize() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let snap = canvas.toolPill.snapButton
        XCTAssertEqual(snap.title, "Snap \(Snapping.defaultGridSize)")
        XCTAssertEqual(snap.style, .tinted)

        snap.performClick(nil)
        XCTAssertFalse(document.model.snappingEnabled)
        XCTAssertEqual(snap.style, .plain)
        XCTAssertEqual(canvas.toastView.text, "Snapping off — S")

        canvas.toolPill.pressSnap(optionHeld: true)
        XCTAssertTrue(canvas.isShowingGridSizePopover)
        XCTAssertFalse(document.model.snappingEnabled, "Option-click doesn't toggle snapping")
        canvas.setGridSize(16)
        XCTAssertEqual(snap.title, "Snap 16")
    }

    @MainActor
    func testThePillNeverTakesFocusOrStartsACanvasGesture() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.makeFirstResponder(canvas.canvasView)
        try XCTUnwrap(canvas.toolPill.toolButtons[.region]).performClick(nil)
        XCTAssertIdentical(window.firstResponder, canvas.canvasView)
        for button in Array(canvas.toolPill.toolButtons.values) + [canvas.toolPill.snapButton] {
            XCTAssertFalse(button.acceptsFirstResponder)
        }
        canvas.canvasView.keyDown(with: try keyEvent("v", keyCode: 9))
        XCTAssertEqual(document.model.tool, .select, "keys still reach the canvas after a click on the pill")

        // A press on the pill, between its buttons or on one, lands on the pill and not on the canvas.
        canvas.view.layoutSubtreeIfNeeded()
        let pill = canvas.toolPill
        for point in [CGPoint(x: pill.bounds.minX + 3, y: pill.bounds.midY), CGPoint(x: pill.bounds.midX, y: 3)] {
            let inSuperview = pill.convert(point, to: canvas.view.superview)
            let hit = try XCTUnwrap(canvas.view.hitTest(inSuperview))
            XCTAssertTrue(hit.isDescendant(of: pill), "\(point) hits \(hit)")
        }
    }

    @MainActor
    func testTooltipsNameReboundKeys() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        XCTAssertEqual(canvas.toolPill.toolButtons[.region]?.toolTip, "Region tool (R)")
        var settings = AppSettings.defaults
        settings.keybindOverrides = [.regionTool: [KeyCombo("b", .shift)]]
        document.model.settings = settings
        canvas.update()
        XCTAssertEqual(canvas.toolPill.toolButtons[.region]?.toolTip, "Region tool (⇧B)")
    }

    @MainActor
    func testTheToastSitsAboveThePill() throws {
        let (_, controller, canvas) = try makeWindow()
        defer { controller.close() }
        canvas.choose(.region)
        canvas.view.layoutSubtreeIfNeeded()
        let toast = canvas.toastView.frame
        let pill = canvas.toolPill.frame
        // The container isn't flipped: up is larger y.
        XCTAssertEqual(toast.minY, pill.maxY + CanvasViewController.toastGap, accuracy: 0.5)
        XCTAssertEqual(pill.minY, CanvasViewController.toolPillInset, accuracy: 0.5)
        XCTAssertEqual(toast.midX, pill.midX, accuracy: 0.5)
    }
}
