import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

final class DocumentTests: XCTestCase {
    private static let examplePackage = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Schema/examples/acme.uidesc")

    private func exampleWrapper() throws -> FileWrapper {
        try FileWrapper(url: Self.examplePackage, options: .immediate)
    }

    private func copyOfExample() throws -> FileWrapper {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        let tree = PackageWrapper.tree(of: try exampleWrapper())
        PackageWrapper.apply(ProjectPackage.Changes(written: tree), to: wrapper)
        return wrapper
    }

    @MainActor
    func testExampleReadsAndWritesBackByteForByte() throws {
        let original = try exampleWrapper()
        let originalTree = PackageWrapper.tree(of: original)
        XCTAssertEqual(originalTree.count, 6)

        let document = Document()
        try document.read(from: original, ofType: AppIdentity.documentTypeIdentifier)
        XCTAssertEqual(document.model.project.screens.count, 5)

        let written = try document.fileWrapper(ofType: AppIdentity.documentTypeIdentifier)
        XCTAssertEqual(PackageWrapper.tree(of: written), originalTree)
    }

    @MainActor
    func testSavingKeepsFilesTheProjectDoesNotOwn() throws {
        let wrapper = try copyOfExample()
        let notes = Data("notes".utf8)
        PackageWrapper.apply(ProjectPackage.Changes(written: ["references/notes.txt": notes]), to: wrapper)

        let document = Document()
        try document.read(from: wrapper, ofType: AppIdentity.documentTypeIdentifier)
        let settings = try XCTUnwrap(document.model.project.screens.first { $0.name == "Settings" })
        try document.perform(ScreenCommands.rename(settings.id, to: "Preferences"))

        let tree = PackageWrapper.tree(of: try document.fileWrapper(ofType: AppIdentity.documentTypeIdentifier))
        XCTAssertEqual(tree["references/notes.txt"], notes)
        XCTAssertNotNil(tree["screens/preferences.json"])
        XCTAssertNil(tree["screens/settings.json"])
    }

    @MainActor
    func testUnsupportedSchemaVersionFailsToRead() throws {
        let wrapper = try copyOfExample()
        let manifest = try XCTUnwrap(PackageWrapper.contents(at: "project.json", in: wrapper))
        let newer = String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        PackageWrapper.apply(ProjectPackage.Changes(written: ["project.json": Data(newer.utf8)]), to: wrapper)

        let document = Document()
        XCTAssertThrowsError(try document.read(from: wrapper, ofType: AppIdentity.documentTypeIdentifier)) {
            XCTAssertEqual($0 as? FormatError, .unsupportedSchemaVersion(found: 2))
        }
    }

    @MainActor
    func testNewDocumentStartsWithTheUntitledProject() {
        let document = Document()
        XCTAssertEqual(document.model.project.screens.map(\.name), ["Screen 1"])
        XCTAssertEqual(document.model.activeScreenID, document.model.project.screens.first?.id)
    }

    @MainActor
    func testCommandsUndoAndRedoThroughTheUndoManager() throws {
        let document = Document()
        let undoManager = try XCTUnwrap(document.undoManager)
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        try document.perform(AddScreen(name: "Settings", viewport: .defaultForNewScreens))
        undoManager.endUndoGrouping()
        XCTAssertEqual(document.model.project.screens.map(\.name), ["Screen 1", "Settings"])
        XCTAssertEqual(undoManager.undoActionName, "New Screen")

        undoManager.undo()
        XCTAssertEqual(document.model.project.screens.map(\.name), ["Screen 1"])
        XCTAssertEqual(undoManager.redoActionName, "New Screen")

        undoManager.redo()
        XCTAssertEqual(document.model.project.screens.map(\.name), ["Screen 1", "Settings"])
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)
    }

    @MainActor
    func testWindowHasAHiddenSidebarCanvasAndHiddenInspector() throws {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        XCTAssertEqual(controller.splitViewController.splitViewItems.count, 3)
        XCTAssertEqual(controller.sidebarItem.behavior, .sidebar)
        XCTAssertTrue(controller.sidebarItem.isCollapsed)
        XCTAssertEqual(controller.inspectorItem.behavior, .inspector)
        XCTAssertTrue(controller.inspectorItem.isCollapsed)
        XCTAssertFalse(controller.canvasItem.isCollapsed)
        controller.close()
    }
}
