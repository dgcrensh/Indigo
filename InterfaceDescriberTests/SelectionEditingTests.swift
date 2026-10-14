import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// Spec Section 7 through the canvas controller and the window's menu items: select all, parent and children,
/// delete, copy, paste, duplicate, nudge, reorder, and showing descriptions.
final class SelectionEditingTests: XCTestCase {
    private static let examplePackage = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Schema/examples/acme.uidesc")

    private let logo = RegionID("8d116ece-1738-47d9-bd9c-172411e20b8f")
    private let form = RegionID("90c192cf-d3ac-44af-8f21-ddb66cad4a26")
    private let email = RegionID("a170b338-3926-4059-b28c-105d1fb17c23")
    private let footer = RegionID("6b4cb242-4a23-4596-a217-beaddbc496cb")
    private let resetPassword = ScreenID("9531985d-5d9d-49f8-9818-e811892f902b")

    /// A window on the example project, showing Login, with a private pasteboard.
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        let wrapper = try FileWrapper(url: Self.examplePackage, options: .immediate)
        try document.read(from: wrapper, ofType: AppIdentity.documentTypeIdentifier)
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        let canvas = controller.canvasController
        canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("indigo-tests-\(UUID().uuidString)"))
        canvas.update()
        XCTAssertEqual(document.model.activeScreen?.name, "Login")
        return (document, controller, canvas)
    }

    /// Runs `body` as one undo group, as one menu command or key press is.
    @MainActor
    private func step(_ document: Document, _ canvas: CanvasViewController, _ body: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        body()
        document.undoManager?.endUndoGrouping()
        canvas.update()
    }

    @MainActor
    private func screen(_ document: Document) throws -> Screen {
        try XCTUnwrap(document.model.activeScreen)
    }

    // MARK: Selecting and deleting

    @MainActor
    func testSelectAllThenDeleteRemovesEveryRegionInOneStep() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        var asked: [String] = []
        canvas.confirmDelete = { message, completion in
            asked.append(message)
            completion(true)
        }

        canvas.selectAll()
        XCTAssertEqual(document.model.selection, login.allRegions.map(\.id))
        step(document, canvas) { canvas.deleteSelection() }
        XCTAssertEqual(asked, ["Delete 3 regions and the 4 regions inside them?"])
        XCTAssertTrue(login.regions.isEmpty)
        XCTAssertEqual(document.model.selection, [])
        XCTAssertEqual(document.model.session.undoDepth, 1)
        XCTAssertEqual(document.undoManager?.undoActionName, "Delete Regions")

        document.undoManager?.undo()
        XCTAssertEqual(login.allRegions.count, 7)
    }

    @MainActor
    func testDeletingAParentAsksAndDecliningDeletesNothing() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        var asked: [String] = []
        canvas.confirmDelete = { message, completion in
            asked.append(message)
            completion(false)
        }

        document.model.selection = [form]
        step(document, canvas) { canvas.deleteSelection() }
        XCTAssertEqual(asked, ["Delete “Sign-in form” and the 4 regions inside it?"])
        XCTAssertEqual(login.allRegions.count, 7)
        XCTAssertEqual(document.model.session.undoDepth, 0)

        document.model.selection = [logo]
        step(document, canvas) { canvas.deleteSelection() }
        XCTAssertEqual(asked.count, 1, "a region with nothing inside is deleted without asking")
        XCTAssertNil(RegionIndex(screen: login).region(logo))
    }

    @MainActor
    func testSelectParentAndChildrenWalkTheTree() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        document.model.selection = [email]
        canvas.selectParent()
        XCTAssertEqual(document.model.selection, [form])
        canvas.selectChildren()
        XCTAssertEqual(document.model.selection, RegionIndex(screen: login).region(form)?.children.map(\.id))
        document.model.selection = [logo]
        canvas.selectParent()
        XCTAssertEqual(document.model.selection, [logo], "a top-level region has no parent to select")
        XCTAssertEqual(document.model.session.undoDepth, 0, "selecting is not an edit")
    }

    // MARK: Clipboard

    @MainActor
    func testCopyAndPasteOntoAnotherScreenKeepsFramesAndLinks() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let original = try XCTUnwrap(document.model.project.region(withID: form)?.region)
        document.model.selection = [form]
        canvas.copySelection()
        XCTAssertEqual(canvas.pasteboard.string(forType: .string), "Sign-in form")
        XCTAssertTrue(canvas.canPaste)

        document.model.activeScreenID = resetPassword
        canvas.update()
        let reset = try screen(document)
        let before = reset.regions.count
        step(document, canvas) { canvas.paste() }
        XCTAssertEqual(reset.regions.count, before + 1)
        let pasted = try XCTUnwrap(reset.regions.last)
        XCTAssertNotEqual(pasted.id, original.id)
        XCTAssertEqual(pasted.subtree.map(\.frame), original.subtree.map(\.frame))
        XCTAssertEqual(pasted.subtree.map(\.links), original.subtree.map(\.links))
        XCTAssertEqual(document.model.selection, [pasted.id])
        XCTAssertEqual(document.undoManager?.undoActionName, "Paste")
        XCTAssertEqual(document.model.session.undoDepth, 1)
    }

    @MainActor
    func testDuplicatePutsACopyOneGridStepAwayAndSelectsIt() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        document.model.selection = [logo]
        step(document, canvas) { canvas.duplicate() }
        XCTAssertEqual(login.regions.count, 4)
        let copy = try XCTUnwrap(login.regions.last)
        XCTAssertEqual(copy.title, "Logo")
        XCTAssertEqual(copy.frame, Frame(x: 156, y: 104, w: 96, h: 96))
        XCTAssertEqual(document.model.selection, [copy.id])
        XCTAssertEqual(document.undoManager?.undoActionName, "Duplicate")
        XCTAssertNil(canvas.pasteboard.data(forType: CanvasViewController.regionsPasteboardType))
    }

    // MARK: Nudging and reordering

    @MainActor
    func testArrowsNudgeByTheGridStepAndShiftArrowsByFour() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let logoRegion = try XCTUnwrap(document.model.project.region(withID: logo)?.region)
        document.model.selection = [logo]
        step(document, canvas) { _ = canvas.canvasKeyDown(KeyCombo("right")) }
        XCTAssertEqual(logoRegion.frame.x, 156)
        step(document, canvas) { _ = canvas.canvasKeyDown(KeyCombo("down", .shift)) }
        XCTAssertEqual(logoRegion.frame.y, 128)
        canvas.toggleSnapping()
        step(document, canvas) { canvas.nudge(.nudgeLeft) }
        XCTAssertEqual(logoRegion.frame.x, 155)
        XCTAssertEqual(document.model.session.undoDepth, 3, "each nudge is a step")
        document.undoManager?.undo()
        XCTAssertEqual(logoRegion.frame.x, 156)
    }

    @MainActor
    func testBringToFrontAndSendToBackAreUndoable() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        document.model.selection = [logo]
        step(document, canvas) { canvas.reorderSelection(to: .front) }
        XCTAssertEqual(login.regions.map(\.id), [form, footer, logo])
        XCTAssertEqual(document.undoManager?.undoActionName, "Bring to Front")
        // Outside an undo group, since an empty group would still count as an undo step in the test's manager.
        canvas.reorderSelection(to: .front)
        XCTAssertEqual(document.model.session.undoDepth, 1, "a region already in front records nothing")
        XCTAssertEqual(document.undoManager?.undoActionName, "Bring to Front")
        document.model.selection = [footer]
        step(document, canvas) { canvas.reorderSelection(to: .back) }
        XCTAssertEqual(login.regions.map(\.id), [footer, form, logo])
        document.undoManager?.undo()
        document.undoManager?.undo()
        XCTAssertEqual(login.regions.map(\.id), [logo, form, footer])
    }

    // MARK: Descriptions

    @MainActor
    func testDAndShiftDShowDescriptionsWithoutAnUndoStep() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let login = try screen(document)
        document.model.selection = [logo]
        canvas.update()
        XCTAssertTrue(canvas.canvasKeyDown(KeyCombo("d")))
        XCTAssertEqual(document.model.project.editorState.visibleDescriptions, [logo])
        XCTAssertEqual(canvas.canvasView.describedLayerIDs, [logo])

        XCTAssertTrue(canvas.canvasKeyDown(KeyCombo("d", .shift)))
        let all = Set(login.allRegions.map(\.id))
        XCTAssertEqual(document.model.project.editorState.visibleDescriptions, all)
        XCTAssertTrue(canvas.canvasView.describedLayerIDs.contains(form))
        canvas.toggleDescriptions(all: true)
        XCTAssertEqual(document.model.project.editorState.visibleDescriptions, [])
        XCTAssertEqual(canvas.canvasView.describedLayerIDs, [])
        XCTAssertEqual(document.model.session.undoDepth, 0)
    }

    // MARK: Menus

    @MainActor
    func testCanvasKeysAreOffWhileTheTitleIsEditedAndOnWithTheCanvasFocused() throws {
        let (document, controller, canvas) = try makeWindow()
        defer { controller.close() }
        let menu = MainMenu.make()
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Edit" }?.submenu)
        let view = try XCTUnwrap(menu.items.first { $0.title == "View" }?.submenu)
        let nudge = try XCTUnwrap(edit.items.first { $0.title == "Nudge" }?.submenu)
        let bareKeyItems = [
            try XCTUnwrap(edit.items.first { $0.title == "Delete" }),
            try XCTUnwrap(edit.items.first { $0.title == "Select Parent" }),
            try XCTUnwrap(edit.items.first { $0.title == "Select Children" }),
            try XCTUnwrap(nudge.items.first { $0.title == "Nudge Left" }),
            try XCTUnwrap(view.items.first { $0.title == "Toggle Description" }),
        ]
        let duplicate = try XCTUnwrap(edit.items.first { $0.title == "Duplicate" })

        try document.model.openDetails(for: email)
        XCTAssertTrue(controller.isEditingText)
        for item in bareKeyItems + [duplicate] {
            XCTAssertFalse(controller.validateMenuItem(item), "\(item.title) is off while typing")
        }

        document.model.closeDetails()
        let window = try XCTUnwrap(controller.window)
        window.makeFirstResponder(canvas.canvasView)
        document.model.selection = [email]
        for item in bareKeyItems + [duplicate] {
            XCTAssertTrue(controller.validateMenuItem(item), "\(item.title) works with the canvas focused")
        }
    }

    @MainActor
    func testEditingMenuItemsHaveTheSpecKeys() throws {
        let menu = MainMenu.make()
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Edit" }?.submenu)
        let view = try XCTUnwrap(menu.items.first { $0.title == "View" }?.submenu)
        let nudge = try XCTUnwrap(edit.items.first { $0.title == "Nudge" }?.submenu)
        let expected: [(NSMenu, String, Selector, String, NSEvent.ModifierFlags)] = [
            (edit, "Duplicate", #selector(DocumentWindowController.duplicateSelection(_:)), "d", .command),
            (edit, "Delete", #selector(DocumentWindowController.deleteSelection(_:)), "\u{8}", []),
            (edit, "Select All", #selector(NSText.selectAll(_:)), "a", .command),
            (edit, "Select Parent", #selector(DocumentWindowController.selectParent(_:)), "\r", .shift),
            (edit, "Select Children", #selector(DocumentWindowController.selectChildren(_:)), "\r", []),
            (edit, "Bring to Front", #selector(DocumentWindowController.bringToFront(_:)), "]", .command),
            (edit, "Send to Back", #selector(DocumentWindowController.sendToBack(_:)), "[", .command),
            (view, "Toggle Description", #selector(DocumentWindowController.toggleDescription(_:)), "d", []),
            (
                view, "Toggle All Descriptions", #selector(DocumentWindowController.toggleAllDescriptions(_:)), "d",
                .shift
            ),
        ]
        for (menu, title, action, key, modifiers) in expected {
            let item = try XCTUnwrap(menu.items.first { $0.title == title }, "\(title) is missing")
            XCTAssertEqual(item.action, action, title)
            XCTAssertEqual(item.keyEquivalent, key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title)
        }
        XCTAssertEqual(nudge.items.filter { !$0.isSeparatorItem }.count, 8)
        let far = try XCTUnwrap(nudge.items.first { $0.title == "Nudge Right Four Steps" })
        XCTAssertEqual(far.keyEquivalentModifierMask, .shift)
        XCTAssertEqual(far.representedObject as? String, KeyAction.nudgeRightFar.rawValue)
    }
}
