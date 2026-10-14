import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// The keybind-suppression audit (milestone 12): while a text field is being edited, no menu item whose key comes
/// from the registry runs unless it is a standard editing shortcut, whatever key it is bound to (spec 6.3 and 9).
final class KeybindAuditTests: XCTestCase {
    /// A window on a new document with a titled region open in the details panel, its title being edited.
    @MainActor
    private func makeWindowEditingATitle() throws -> (Document, DocumentWindowController) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        let screen = try XCTUnwrap(document.model.activeScreen)
        let create = CreateRegion(screen: screen.id, frame: Frame(x: 16, y: 16, w: 80, h: 40), title: "Box")
        try document.perform(create)
        controller.canvasController.update()
        try document.model.openDetails(for: create.id)
        XCTAssertTrue(controller.isEditingText, "the title has focus when the panel opens")
        return (document, controller)
    }

    /// Every item in `menu` and its submenus whose key comes from the registry.
    @MainActor
    private func registryItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            let own = MainMenu.keybind(of: item) == nil ? [] : [item]
            return own + (item.submenu.map(registryItems(in:)) ?? [])
        }
    }

    /// Whether `item` is enabled, asked of the object that handles it in the window.
    @MainActor
    private func isEnabled(_ item: NSMenuItem, in controller: DocumentWindowController) -> Bool {
        if item.action == #selector(NSSplitViewController.toggleSidebar(_:)) {
            return controller.splitViewController.validateUserInterfaceItem(item)
        }
        return controller.validateMenuItem(item)
    }

    /// Checks that, of the registry's items, only the standard editing shortcuts can run while text is being edited.
    @MainActor
    private func assertOnlyEditingShortcutsRun(
        in menu: NSMenu, _ controller: DocumentWindowController, file: StaticString = #filePath, line: UInt = #line
    ) {
        let items = registryItems(in: menu)
        XCTAssertEqual(
            Set(items.compactMap { MainMenu.keybind(of: $0)?.action }), Set(KeyAction.allCases),
            "every keybind action is in the menu bar (spec 9)", file: file, line: line)
        for item in items {
            let action = MainMenu.keybind(of: item)!.action
            if action.worksWhileEditingText {
                XCTAssertTrue(controller.allowsKeybindItem(item), "\(item.title) works in text", file: file, line: line)
            } else {
                XCTAssertFalse(isEnabled(item, in: controller), "\(item.title) is off in text", file: file, line: line)
            }
        }
    }

    @MainActor
    func testOnlyEditingShortcutsRunWhileTheTitleIsEdited() throws {
        let (_, controller) = try makeWindowEditingATitle()
        defer { controller.close() }
        assertOnlyEditingShortcutsRun(in: MainMenu.make(), controller)
    }

    @MainActor
    func testOnlyEditingShortcutsRunWhileTheDescriptionIsEdited() throws {
        let (_, controller) = try makeWindowEditingATitle()
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.makeFirstResponder(controller.detailsController.descriptionView))
        XCTAssertTrue(controller.isEditingText)
        assertOnlyEditingShortcutsRun(in: MainMenu.make(), controller)
    }

    @MainActor
    func testZoomAndSidebarAreOffWhileTypingAndOnAgainOnTheCanvas() throws {
        let (document, controller) = try makeWindowEditingATitle()
        defer { controller.close() }
        let items = registryItems(in: MainMenu.make())
        let zoomAndSidebar = items.filter {
            [.zoomIn, .zoomOut, .actualSize, .toggleSidebar].contains(MainMenu.keybind(of: $0)?.action)
        }
        XCTAssertEqual(zoomAndSidebar.count, 5, "Zoom In twice, Zoom Out, Actual Size and Toggle Sidebar")
        for item in zoomAndSidebar {
            XCTAssertFalse(isEnabled(item, in: controller), "\(item.title) while typing")
        }

        document.model.closeDetails()
        let window = try XCTUnwrap(controller.window)
        window.makeFirstResponder(controller.canvasController.canvasView)
        XCTAssertFalse(controller.isEditingText)
        for item in zoomAndSidebar {
            XCTAssertTrue(isEnabled(item, in: controller), "\(item.title) with the canvas focused")
        }
        for item in items {
            XCTAssertTrue(controller.allowsKeybindItem(item), "\(item.title) isn't held back outside text")
        }
    }

    @MainActor
    func testABareKeyOverrideIsOffWhileTypingToo() throws {
        let (_, controller) = try makeWindowEditingATitle()
        defer { controller.close() }
        let menu = MainMenu.make()
        MainMenu.applyKeybinds(KeybindRegistry(overrides: [.zoomIn: [KeyCombo("z")]]), to: menu)
        let zoomIn = try XCTUnwrap(registryItems(in: menu).first { MainMenu.keybind(of: $0)?.action == .zoomIn })
        XCTAssertEqual(zoomIn.keyEquivalent, "z")
        XCTAssertEqual(zoomIn.keyEquivalentModifierMask, [])
        XCTAssertFalse(isEnabled(zoomIn, in: controller))
        assertOnlyEditingShortcutsRun(in: menu, controller)
    }
}
