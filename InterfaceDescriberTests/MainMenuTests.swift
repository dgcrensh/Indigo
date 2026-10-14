import AppKit
import XCTest

@testable import InterfaceDescriber

final class MainMenuTests: XCTestCase {
    @MainActor
    private func item(_ title: String, in menuTitle: String) throws -> NSMenuItem {
        let menu = try XCTUnwrap(MainMenu.make().items.first { $0.title == menuTitle }?.submenu)
        return try XCTUnwrap(menu.items.first { $0.title == title }, "\(menuTitle) > \(title) is missing")
    }

    @MainActor
    func testFileMenuHasTheDocumentCommands() throws {
        XCTAssertEqual(try item("Save As…", in: "File").action, #selector(NSDocument.saveAs(_:)))
        XCTAssertEqual(try item("Revert to Saved", in: "File").action, #selector(NSDocument.revertToSaved(_:)))
        XCTAssertEqual(try item("Duplicate", in: "File").action, #selector(NSDocument.duplicate(_:)))
        let recent = try XCTUnwrap(try item("Open Recent", in: "File").submenu)
        XCTAssertTrue(recent.items.contains { $0.action == #selector(NSDocumentController.clearRecentDocuments(_:)) })
    }

    @MainActor
    func testViewMenuHasTheZoomCommands() throws {
        let zoomIn = try item("Zoom In", in: "View")
        XCTAssertEqual(zoomIn.action, #selector(DocumentWindowController.zoomIn(_:)))
        XCTAssertEqual(zoomIn.keyEquivalent, "+")
        XCTAssertEqual(zoomIn.keyEquivalentModifierMask, .command)
        let zoomOut = try item("Zoom Out", in: "View")
        XCTAssertEqual(zoomOut.action, #selector(DocumentWindowController.zoomOut(_:)))
        XCTAssertEqual(zoomOut.keyEquivalent, "-")
        let actualSize = try item("Actual Size", in: "View")
        XCTAssertEqual(actualSize.action, #selector(DocumentWindowController.actualSize(_:)))
        XCTAssertEqual(actualSize.keyEquivalent, "0")
        XCTAssertEqual(actualSize.keyEquivalentModifierMask, .command)
    }

    @MainActor
    func testControlCommandSTogglesTheSidebar() throws {
        let toggle = try item("Toggle Sidebar", in: "View")
        XCTAssertEqual(toggle.action, #selector(NSSplitViewController.toggleSidebar(_:)))
        XCTAssertEqual(toggle.keyEquivalent, "s")
        XCTAssertEqual(toggle.keyEquivalentModifierMask, [.control, .command])
    }
}
