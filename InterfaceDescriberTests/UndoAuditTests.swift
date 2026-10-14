import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// The undo audit (milestone 12): every edit a user can make through the canvas, the Edit menu, the details panel and
/// the Screen menu or sidebar is one undo step whose undo restores the package's content files byte for byte and whose
/// redo reproduces them; every editor-only action adds no step and changes no content file (spec Section 13, Quality).
final class UndoAuditTests: XCTestCase {
    private static let examplePackage = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Schema/examples/acme.uidesc")

    private static let login = ScreenID("6513270e-269e-4d37-b2a7-4de452e6b438")
    private static let loginDesktop = ScreenID("d23f0824-128b-4f33-8c5c-7fd0a6a3a450")
    private static let reset = ScreenID("9531985d-5d9d-49f8-9818-e811892f902b")
    private static let settings = ScreenID("36f675cc-81e7-4ef5-a8e2-5d940ed90475")
    private static let accountMenu = ScreenID("6b0d549b-6f03-475a-9600-a35a099950d8")
    private static let logo = RegionID("8d116ece-1738-47d9-bd9c-172411e20b8f")
    private static let form = RegionID("90c192cf-d3ac-44af-8f21-ddb66cad4a26")
    private static let signIn = RegionID("0cb1e29c-658c-4a14-95e6-0af593bd04cf")
    private static let forgotPassword = RegionID("8e81973e-0bec-47b0-b898-d190f9ebdacc")
    private static let footer = RegionID("6b4cb242-4a23-4596-a217-beaddbc496cb")
    private static let settingsList = RegionID("9be4bcfc-49b6-4a08-b2e6-cc3ababced20")
    private static let ipad = Viewport(preset: "ipad", width: 820, height: 1180)

    /// A document window on the example project and the parts the paths drive.
    private struct Window {
        let document: Document
        let controller: DocumentWindowController
        var canvas: CanvasViewController { controller.canvasController }
        var screens: ScreenController { controller.screenController }
        var panel: DetailsPanelController { controller.detailsController }
        var model: DocumentModel { document.model }
    }

    /// One thing a user does, starting from `selecting`. `setup` runs first in its own undo group; `body` is the action under audit, run as one
    /// undo group like one event or menu command.
    private struct Path {
        let name: String
        var screen: ScreenID = UndoAuditTests.login
        /// The selection `setup` starts from.
        var selecting: [RegionID] = []
        var setup: @MainActor (Window) throws -> Void = { _ in }
        let body: @MainActor (Window) throws -> Void
    }

    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "indigo-undo-audit-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    /// A window on the example project showing `screen`, with every question the app would ask answered yes and a
    /// private pasteboard and settings file.
    @MainActor
    private func makeWindow(showing screen: ScreenID) throws -> Window {
        let document = Document()
        let wrapper = try FileWrapper(url: Self.examplePackage, options: .immediate)
        try document.read(from: wrapper, ofType: AppIdentity.documentTypeIdentifier)
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        controller.settingsStore = SettingsStore(url: temporaryDirectory.appendingPathComponent("settings.json"))
        let window = Window(document: document, controller: controller)
        window.canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("indigo-undo-audit-\(UUID().uuidString)"))
        window.canvas.confirmDelete = { _, completion in completion(true) }
        window.screens.confirm = { _, _, completion in completion(true) }
        window.screens.askName = { _, _, completion in completion("Tablet") }
        window.screens.askSize = { _, completion in completion((width: 500, height: 400)) }
        window.screens.chooseLink = { targets, _, completion in completion(targets.first) }
        window.screens.displaySize = { CGSize(width: 1512, height: 982) }
        window.model.show(screen)
        window.canvas.update()
        return window
    }

    /// Everything the project writes except `.editor-state.json`: the files readers of the description see.
    @MainActor
    private func content(_ window: Window) -> PackageTree {
        var tree = ProjectPackage.write(project: window.model.project).tree
        tree[ProjectPackage.editorStatePath] = nil
        return tree
    }

    @MainActor
    private func group(_ window: Window, _ body: () throws -> Void) rethrows {
        let undoManager = window.document.undoManager
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.endUndoGrouping()
            window.canvas.update()
        }
        try body()
    }

    // MARK: Gestures and panel input, as the canvas view and the panel's controls send them

    @MainActor
    private func drag(_ window: Window, from start: CGPoint, to end: CGPoint, modifiers: KeyCombo.Modifiers = []) {
        window.canvas.canvasPressed(at: start, modifiers: modifiers)
        window.canvas.canvasDragged(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), optionHeld: false)
        window.canvas.canvasDragged(to: end, optionHeld: false)
        window.canvas.canvasReleased(at: end, optionHeld: false)
    }

    @MainActor
    private func click(_ window: Window, at point: CGPoint, modifiers: KeyCombo.Modifiers = []) {
        window.canvas.canvasPressed(at: point, modifiers: modifiers)
        window.canvas.canvasReleased(at: point, optionHeld: false)
    }

    @MainActor
    private func select(_ regions: [RegionID], in window: Window) {
        window.model.selection = regions
        window.canvas.update()
    }

    @MainActor
    private func type(_ text: String, into field: NSTextField, of panel: DetailsPanelController) {
        field.stringValue = text
        panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    @MainActor
    private func typeDescription(_ text: String, in panel: DetailsPanelController) {
        panel.descriptionView.string = text
        panel.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.descriptionView))
    }

    @MainActor
    private func pressEscape(in panel: DetailsPanelController) {
        _ = panel.control(
            panel.titleField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    }

    // MARK: Edits

    @MainActor
    private var editPaths: [Path] {
        [
            // Canvas gestures (spec 5)
            Path(name: "Draw a region and title it") { window in
                window.canvas.choose(.region)
                self.drag(window, from: CGPoint(x: 200, y: 560), to: CGPoint(x: 300, y: 620))
                self.type("Banner", into: window.panel.titleField, of: window.panel)
                self.pressEscape(in: window.panel)
            },
            Path(name: "Move a region") { window in
                self.drag(window, from: CGPoint(x: 196, y: 144), to: CGPoint(x: 212, y: 160))
            },
            Path(name: "Drag a region into another") { window in
                self.drag(window, from: CGPoint(x: 196, y: 144), to: CGPoint(x: 196, y: 444))
                let screen = try XCTUnwrap(window.model.activeScreen)
                XCTAssertEqual(RegionIndex(screen: screen).parent(of: Self.logo)?.id, Self.form)
            },
            Path(name: "Resize a region", selecting: [Self.logo]) { window in
                self.drag(window, from: CGPoint(x: 244, y: 192), to: CGPoint(x: 260, y: 208))
            },
            Path(name: "Move a multi-selection", selecting: [Self.logo, Self.footer]) { window in
                self.drag(window, from: CGPoint(x: 196, y: 144), to: CGPoint(x: 196, y: 120))
            },
            // Edit menu and keys (spec 7)
            Path(name: "Nudge", selecting: [Self.logo]) { window in
                window.canvas.nudge(.nudgeRight)
            },
            Path(name: "Nudge four steps", selecting: [Self.logo]) { window in
                window.canvas.nudge(.nudgeDownFar)
            },
            Path(name: "Delete a region", selecting: [Self.footer]) { window in
                window.canvas.deleteSelection()
            },
            Path(name: "Delete a region and its children", selecting: [Self.form]) { window in
                window.canvas.deleteSelection()
            },
            Path(
                name: "Paste",
                setup: { window in
                    self.select([Self.logo], in: window)
                    window.canvas.copySelection()
                },
                body: { window in
                    window.canvas.paste()
                }
            ),
            Path(
                name: "Paste onto another screen",
                setup: { window in
                    self.select([Self.form], in: window)
                    window.canvas.copySelection()
                    window.model.show(Self.reset)
                },
                body: { window in
                    window.canvas.paste()
                }
            ),
            Path(name: "Duplicate", selecting: [Self.signIn]) { window in
                window.canvas.duplicate()
            },
            Path(name: "Bring to front", selecting: [Self.logo]) { window in
                window.canvas.reorderSelection(to: .front)
            },
            Path(name: "Send to back", selecting: [Self.footer]) { window in
                window.canvas.reorderSelection(to: .back)
            },
            // Details panel (spec 6)
            Path(name: "Edit every field in the panel") { window in
                let panel = window.panel
                try window.model.openDetails(for: Self.logo)
                self.type("Brand mark", into: panel.titleField, of: panel)
                self.typeDescription("The logo, larger.", in: panel)
                panel.kindChips.choose(.button)
                panel.addLink(nil)
                panel.scrollsCheckbox.state = .on
                panel.scrollsChanged(nil)
                self.pressEscape(in: panel)
                XCTAssertEqual(window.document.undoManager?.undoActionName, "Edit Region")
            },
            Path(name: "Turn a region's scrolling off in the panel", screen: Self.settings) { window in
                try window.model.openDetails(for: Self.settingsList)
                window.panel.scrollsCheckbox.state = .off
                window.panel.scrollsChanged(nil)
                self.pressEscape(in: window.panel)
            },
            // Screen menu and sidebar (spec 8)
            Path(name: "New screen") { window in window.screens.newScreen() },
            Path(name: "Duplicate screen") { window in window.screens.duplicateScreen(Self.settings) },
            Path(name: "Rename screen") { window in window.screens.promptRename(Self.reset) },
            Path(name: "Delete a screen others link to") { window in window.screens.deleteScreen(Self.accountMenu) },
            Path(name: "Reorder screens") { window in window.screens.moveRows([4], to: 0) },
            Path(name: "Change screen kind") { window in window.screens.setKind(.sheet, of: Self.reset) },
            Path(name: "Choose a viewport preset") { window in window.screens.setViewport(Self.ipad, of: Self.reset) },
            Path(name: "Choose a custom size") { window in window.screens.chooseCustomSize(for: Self.reset) },
            Path(name: "Type a viewport size") { window in
                window.screens.setSize(width: 400, height: 900, of: Self.reset)
            },
            Path(name: "Use This Device") { window in window.screens.useThisDevice(for: Self.reset) },
            Path(
                name: "Refresh This Device",
                setup: { window in
                    window.screens.useThisDevice(for: Self.reset)
                    window.screens.displaySize = { CGSize(width: 1728, height: 1117) }
                },
                body: { window in
                    window.screens.refreshThisDevice(for: Self.reset)
                }
            ),
            Path(name: "Save a viewport as a preset") { window in
                window.screens.saveViewportAsPreset(for: Self.reset)
            },
            Path(name: "Turn screen scrolling on") { window in window.screens.setScrolls(true, of: Self.reset) },
            Path(
                name: "Change screen scrolling",
                setup: { window in window.screens.setScrolls(true, of: Self.reset) },
                body: { window in window.screens.setScroll(axis: .both, height: 2000, of: Self.reset) }
            ),
            Path(name: "New variant") { window in window.screens.newVariant(of: Self.settings, viewport: Self.ipad) },
            Path(name: "Make variant of") { window in window.screens.makeVariant(Self.accountMenu, of: Self.reset) },
            Path(name: "Remove from variant group") { window in
                window.screens.removeFromVariantGroup(Self.loginDesktop)
            },
            Path(name: "Rename variant group") { window in
                window.screens.promptRenameVariantGroup(containing: Self.login)
            },
            Path(name: "Ungroup variants") { window in window.screens.ungroupVariants(containing: Self.login) },
        ]
    }

    @MainActor
    func testEveryEditIsOneUndoStepThatUndoesAndRedoesToTheSameBytes() throws {
        for path in editPaths {
            let window = try makeWindow(showing: path.screen)
            defer { window.controller.close() }
            let undoManager = try XCTUnwrap(window.document.undoManager)
            select(path.selecting, in: window)
            try group(window) { try path.setup(window) }
            let depth = window.model.session.undoDepth
            let before = content(window)

            try group(window) { try path.body(window) }
            XCTAssertNil(window.model.details, "\(path.name): the panel is closed")
            XCTAssertEqual(window.model.session.undoDepth, depth + 1, "\(path.name) is one step")
            let after = content(window)
            XCTAssertNotEqual(after, before, "\(path.name) changed the project")

            undoManager.undo()
            window.canvas.update()
            XCTAssertEqual(content(window), before, "undo of \(path.name)")
            XCTAssertEqual(window.model.session.undoDepth, depth, "undo of \(path.name)")

            undoManager.redo()
            window.canvas.update()
            XCTAssertEqual(content(window), after, "redo of \(path.name)")
            XCTAssertEqual(window.model.session.undoDepth, depth + 1, "redo of \(path.name)")
        }
    }

    // MARK: Editor-only actions

    @MainActor
    private var editorOnlyPaths: [Path] {
        [
            Path(name: "Choose the Region tool") { window in window.canvas.choose(.region) },
            Path(name: "Choose the Write tool") { window in window.canvas.choose(.write) },
            Path(name: "Toggle snapping") { window in window.canvas.toggleSnapping() },
            Path(name: "Change the grid size") { window in window.canvas.setGridSize(16) },
            Path(name: "Click a region") { window in self.click(window, at: CGPoint(x: 196, y: 144)) },
            Path(name: "Marquee") { window in
                self.drag(window, from: CGPoint(x: 4, y: 4), to: CGPoint(x: 300, y: 300))
            },
            Path(name: "Select all") { window in window.canvas.selectAll() },
            Path(name: "Select parent", selecting: [Self.signIn]) { window in
                window.canvas.selectParent()
            },
            Path(name: "Select children", selecting: [Self.form]) { window in
                window.canvas.selectChildren()
            },
            Path(name: "Copy", selecting: [Self.logo]) { window in
                window.canvas.copySelection()
            },
            Path(name: "Toggle a description", selecting: [Self.logo]) { window in
                window.canvas.toggleDescriptions(all: false)
            },
            Path(name: "Toggle all descriptions") { window in window.canvas.toggleDescriptions(all: true) },
            Path(name: "Zoom in") { window in window.canvas.zoomIn() },
            Path(name: "Zoom out") { window in window.canvas.zoomOut() },
            Path(name: "Actual size") { window in window.canvas.actualSize() },
            Path(
                name: "Scroll inside a region", screen: Self.settings,
                selecting: [Self.settingsList]
            ) { window in
                window.canvas.canvasScroll(Self.settingsList, byViewDX: 0, dy: -120)
            },
            Path(name: "Next screen") { window in window.screens.showNextScreen() },
            Path(name: "Previous screen", screen: Self.reset) { window in window.screens.showPreviousScreen() },
            Path(name: "Follow a link with L", selecting: [Self.forgotPassword]) {
                window in
                window.canvas.followSelectedLink()
                XCTAssertEqual(window.model.activeScreenID, Self.reset)
            },
            Path(name: "Follow a link with Cmd-click") { window in
                self.click(window, at: CGPoint(x: 100, y: 408), modifiers: .command)
                XCTAssertEqual(window.model.activeScreenID, Self.settings)
            },
            Path(
                name: "Go back",
                setup: { window in
                    self.select([Self.forgotPassword], in: window)
                    window.canvas.followSelectedLink()
                },
                body: { window in
                    window.screens.goBack()
                    XCTAssertEqual(window.model.activeScreenID, Self.login)
                }
            ),
            Path(name: "Open and close a region without changes") { window in
                try window.model.openDetails(for: Self.logo)
                self.pressEscape(in: window.panel)
            },
            Path(name: "Draw a region and leave its title blank") { window in
                window.canvas.choose(.region)
                self.drag(window, from: CGPoint(x: 200, y: 560), to: CGPoint(x: 300, y: 620))
                self.pressEscape(in: window.panel)
            },
        ]
    }

    @MainActor
    func testEditorOnlyActionsAddNoStepAndChangeNoContent() throws {
        for path in editorOnlyPaths {
            let window = try makeWindow(showing: path.screen)
            defer { window.controller.close() }
            select(path.selecting, in: window)
            try group(window) { try path.setup(window) }
            let depth = window.model.session.undoDepth
            let before = content(window)

            try group(window) { try path.body(window) }
            XCTAssertNil(window.model.details, "\(path.name): the panel is closed")
            XCTAssertEqual(window.model.session.undoDepth, depth, "\(path.name) adds no step")
            XCTAssertEqual(content(window), before, "\(path.name) changes no content file")
        }
    }
}
