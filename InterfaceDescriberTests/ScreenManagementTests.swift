import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// Spec Section 8 through the screen controller, the canvas and the window's menu items: screens, viewports,
/// presets, variants, following links, and the link indicator.
final class ScreenManagementTests: XCTestCase {
    private static let examplePackage = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Schema/examples/acme.uidesc")

    private let login = ScreenID("6513270e-269e-4d37-b2a7-4de452e6b438")
    private let loginDesktop = ScreenID("d23f0824-128b-4f33-8c5c-7fd0a6a3a450")
    private let reset = ScreenID("9531985d-5d9d-49f8-9818-e811892f902b")
    private let settings = ScreenID("36f675cc-81e7-4ef5-a8e2-5d940ed90475")
    private let accountMenu = ScreenID("6b0d549b-6f03-475a-9600-a35a099950d8")
    private let forgotPassword = RegionID("8e81973e-0bec-47b0-b898-d190f9ebdacc")
    private let signIn = RegionID("0cb1e29c-658c-4a14-95e6-0af593bd04cf")

    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "indigo-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private var settingsURL: URL {
        temporaryDirectory.appendingPathComponent("settings.json")
    }

    /// A window on the example project, showing Login, with presets in a temporary settings file.
    @MainActor
    private func makeWindow() throws -> (Document, DocumentWindowController, ScreenController) {
        let document = Document()
        let wrapper = try FileWrapper(url: Self.examplePackage, options: .immediate)
        try document.read(from: wrapper, ofType: AppIdentity.documentTypeIdentifier)
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        controller.screenController.presetStore = UserPresetStore(url: settingsURL)
        controller.canvasController.update()
        XCTAssertEqual(document.model.activeScreenID, login)
        return (document, controller, controller.screenController)
    }

    /// Runs `body` as one undo group, as one menu command is.
    @MainActor
    private func step(_ document: Document, _ body: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        body()
        document.undoManager?.endUndoGrouping()
    }

    @MainActor
    private func order(_ document: Document) -> [ScreenID] {
        document.model.project.screens.map(\.id)
    }

    // MARK: Screens

    @MainActor
    func testANewScreenGoesAfterTheActiveGroupAndShowsAndUndoShowsItsNeighbour() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        step(document) { screens.newScreen() }
        let added = try XCTUnwrap(document.model.activeScreen)
        XCTAssertEqual(added.name, "Screen 1")
        XCTAssertEqual(order(document), [login, loginDesktop, added.id, reset, settings, accountMenu])
        XCTAssertEqual(document.undoManager?.undoActionName, "New Screen")
        XCTAssertEqual(document.model.project.editorState.lastActiveScreen, added.id)

        document.undoManager?.undo()
        XCTAssertEqual(order(document), [login, loginDesktop, reset, settings, accountMenu])
        XCTAssertEqual(document.model.activeScreenID, reset, "the screen that took its place shows")
    }

    @MainActor
    func testEachScreenActionIsOneNamedStep() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        let undoManager = try XCTUnwrap(document.undoManager)
        let ipad = Viewport(preset: "ipad", width: 820, height: 1180)
        let actions: [(String, () -> Void)] = [
            ("Duplicate Screen", { screens.duplicateScreen(self.settings) }),
            ("Rename Screen", { screens.renameScreen(self.reset, to: "  Recover  ") }),
            ("Change Screen Kind", { screens.setKind(.sheet, of: self.reset) }),
            ("Change Viewport", { screens.setViewport(ipad, of: self.reset) }),
            ("Change Viewport", { screens.setSize(width: 500, height: 400, of: self.reset) }),
            ("Move Screen", { screens.moveRows([4], to: 0) }),
            ("New Variant", { screens.newVariant(of: self.settings, viewport: ipad) }),
            ("Make Variant", { screens.makeVariant(self.accountMenu, of: self.reset) }),
            ("Remove from Variant Group", { screens.removeFromVariantGroup(self.loginDesktop) }),
            ("Rename Variant Group", { screens.renameVariantGroup(containing: self.reset, to: "Recovery") }),
        ]
        for (index, (name, action)) in actions.enumerated() {
            step(document) { action() }
            XCTAssertEqual(document.model.session.undoDepth, index + 1, name)
            XCTAssertEqual(undoManager.undoActionName, name)
        }
        let project = document.model.project
        XCTAssertEqual(project.screen(withID: reset)?.name, "Recover")
        XCTAssertEqual(project.screen(withID: reset)?.viewport, Viewport(width: 500, height: 400))
        XCTAssertEqual(order(document).first, settings)
        XCTAssertEqual(document.model.activeScreen?.name, "Settings (iPad)", "the new variant shows")

        // Blank and unchanged edits add no step.
        screens.renameScreen(reset, to: "  ")
        screens.setKind(.sheet, of: reset)
        screens.setSize(width: 500, height: 400, of: reset)
        XCTAssertEqual(document.model.session.undoDepth, actions.count)

        for _ in actions {
            undoManager.undo()
        }
        XCTAssertEqual(order(document), [login, loginDesktop, reset, settings, accountMenu])
        XCTAssertEqual(project.screen(withID: reset)?.name, "Reset Password")
    }

    @MainActor
    func testDeletingALinkedScreenAsksFirstAndRemovesItsLinks() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        var asked: [String] = []
        var answer = false
        screens.confirm = { message, _, completion in
            asked.append(message)
            completion(answer)
        }
        step(document) { screens.deleteScreen(reset) }
        XCTAssertEqual(
            asked, ["Delete “Reset Password”? 2 regions on other screens link to it, and those links will be removed."])
        XCTAssertEqual(document.model.session.undoDepth, 0, "declining deletes nothing")

        answer = true
        step(document) { screens.deleteScreen(reset) }
        XCTAssertNil(document.model.project.screen(withID: reset))
        XCTAssertEqual(document.model.project.region(withID: forgotPassword)?.region.links, [])
        XCTAssertEqual(document.undoManager?.undoActionName, "Delete Screen")
        document.undoManager?.undo()
        XCTAssertEqual(document.model.project.region(withID: forgotPassword)?.region.links.map(\.screen), [reset])

        // Nothing links to Login (Desktop), so it goes without asking.
        asked = []
        step(document) { screens.deleteScreen(loginDesktop) }
        XCTAssertEqual(asked, [])
        XCTAssertNil(document.model.project.screen(withID: loginDesktop))
    }

    @MainActor
    func testTheOnlyScreenCantBeDeleted() throws {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        defer { controller.close() }
        let item = NSMenuItem(
            title: "Delete Screen…", action: #selector(DocumentWindowController.deleteScreen(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))
        controller.deleteScreen(nil)
        XCTAssertEqual(document.model.project.screens.count, 1)
    }

    @MainActor
    func testTheActiveScreenIsSavedWhenTheUserChangesIt() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        XCTAssertNil(document.model.project.editorState.lastActiveScreen, "reading a document doesn't set it")
        screens.showNextScreen()
        XCTAssertEqual(document.model.activeScreenID, loginDesktop)
        XCTAssertEqual(document.model.project.editorState.lastActiveScreen, loginDesktop)
        let tree = PackageWrapper.tree(of: try document.fileWrapper(ofType: AppIdentity.documentTypeIdentifier))
        let state = String(decoding: try XCTUnwrap(tree[".editor-state.json"]), as: UTF8.self)
        XCTAssertTrue(state.contains(loginDesktop.rawValue))
    }

    // MARK: Viewports

    @MainActor
    func testThisDeviceUsesTheMeasuredDisplayAndRefreshMeasuresAgain() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        var display = CGSize(width: 1512, height: 982)
        screens.displaySize = { display }

        step(document) { screens.useThisDevice(for: login) }
        XCTAssertEqual(
            document.model.activeScreen?.viewport,
            Viewport(preset: ViewportPresets.thisDeviceID, width: 1512, height: 982))
        let refresh = NSMenuItem(
            title: "", action: #selector(DocumentWindowController.refreshThisDevice(_:)), keyEquivalent: "")
        XCTAssertTrue(controller.validateMenuItem(refresh))

        display = CGSize(width: 1728, height: 1117)
        step(document) { controller.refreshThisDevice(nil) }
        XCTAssertEqual(document.model.activeScreen?.viewport.width, 1728)
        XCTAssertEqual(document.model.session.undoDepth, 2)

        step(document) { screens.setViewport(.defaultForNewScreens, of: login) }
        XCTAssertFalse(controller.validateMenuItem(refresh), "only a This Device viewport refreshes")
    }

    @MainActor
    func testASavedPresetReachesTheSettingsFileAndTheViewportMenu() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        screens.askName = { _, _, completion in completion("Watch") }
        step(document) { screens.setSize(width: 198, height: 242, of: login) }
        step(document) { screens.saveViewportAsPreset(for: login) }

        let file = String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self)
        XCTAssertEqual(
            file,
            "{\n  \"viewportPresets\": [\n    {\n      \"name\": \"Watch\",\n      \"width\": 198,\n"
                + "      \"height\": 242\n    }\n  ]\n}\n")
        XCTAssertEqual(document.model.activeScreen?.viewport, Viewport(preset: "watch", width: 198, height: 242))

        let menu = NSMenu()
        controller.populateViewportMenu(menu)
        let item = try XCTUnwrap(menu.items.first { $0.title == "Watch (198 × 242)" })
        XCTAssertEqual(controller.validateMenuItem(item), true)
        XCTAssertEqual(item.state, .on)
        XCTAssertTrue(menu.items.contains { $0.title == "iPhone 15 (393 × 852)" })

        // A preset read from the file at launch is offered too.
        XCTAssertEqual(UserPresetStore(url: settingsURL).presets.map(\.name), ["Watch"])
    }

    @MainActor
    func testABadSettingsFileIsLeftAloneAndShownAsAnError() throws {
        let (_, controller, screens) = try makeWindow()
        defer { controller.close() }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let bad = Data("{ \"viewportPresets\": [ oops".utf8)
        try bad.write(to: settingsURL)
        var errors: [String] = []
        screens.showError = { errors.append($0.localizedDescription) }
        screens.askName = { _, _, completion in completion("Watch") }

        screens.saveViewportAsPreset(for: login)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("settings.json: line 1"), errors[0])
        XCTAssertEqual(try Data(contentsOf: settingsURL), bad)
    }

    // MARK: Following links

    @MainActor
    func testCommandClickAndLFollowLinksAndBackAndForwardReturn() throws {
        let (document, controller, _) = try makeWindow()
        defer { controller.close() }
        let canvas = controller.canvasController
        let back = NSMenuItem(title: "", action: #selector(DocumentWindowController.goBack(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(back))

        // Cmd-click "Forgot password" (32, 456, 140 × 24) on Login.
        canvas.canvasPressed(at: CGPoint(x: 60, y: 466), modifiers: .command, clickCount: 1)
        canvas.canvasReleased(at: CGPoint(x: 60, y: 466), optionHeld: false)
        canvas.update()
        XCTAssertEqual(document.model.activeScreenID, reset)
        XCTAssertEqual(document.model.session.undoDepth, 0, "following a link isn't an edit")
        XCTAssertTrue(controller.validateMenuItem(back))

        controller.goBack(nil)
        canvas.update()
        XCTAssertEqual(document.model.activeScreenID, login)
        controller.goForward(nil)
        canvas.update()
        XCTAssertEqual(document.model.activeScreenID, reset)
        controller.goBack(nil)
        canvas.update()

        // `L` with the region selected.
        document.model.selection = [forgotPassword]
        canvas.update()
        XCTAssertTrue(canvas.canFollowLink)
        XCTAssertTrue(canvas.canvasKeyDown(KeyCombo("l")))
        canvas.update()
        XCTAssertEqual(document.model.activeScreenID, reset)
        XCTAssertEqual(document.model.selection, [], "the new screen starts with nothing selected")
    }

    @MainActor
    func testAChooserPicksAmongSeveralLinks() throws {
        let (document, controller, screens) = try makeWindow()
        defer { controller.close() }
        let canvas = controller.canvasController
        try document.perform(
            RegionCommands.setLinks(
                [Link(screen: reset, trigger: "click"), Link(screen: accountMenu, trigger: "right-click")],
                of: forgotPassword))
        var offered: [String] = []
        screens.chooseLink = { targets, _, completion in
            offered = targets.map(\.title)
            completion(targets[1])
        }
        document.model.selection = [forgotPassword]
        canvas.update()
        canvas.followSelectedLink()
        XCTAssertEqual(offered, ["Reset Password — click", "Account Menu — right-click"])
        XCTAssertEqual(document.model.activeScreenID, accountMenu)
    }

    @MainActor
    func testLinkedRegionsShowTheLinkIndicator() throws {
        let (document, controller, _) = try makeWindow()
        defer { controller.close() }
        let canvas = controller.canvasController
        XCTAssertEqual(canvas.canvasView.linkedLayerIDs, [signIn, forgotPassword])

        try document.perform(RegionCommands.setLinks([], of: signIn))
        canvas.update()
        XCTAssertEqual(canvas.canvasView.linkedLayerIDs, [forgotPassword])
    }

    // MARK: Menus

    @MainActor
    func testScreenAndGoMenusHaveTheirItemsAndKeys() throws {
        let mainMenu = MainMenu.make()
        let screenMenu = try XCTUnwrap(mainMenu.items.first { $0.title == "Screen" }?.submenu)
        for title in [
            "New Screen", "Duplicate Screen", "Rename Screen…", "Delete Screen…", "Kind", "Viewport", "New Variant",
            "Make Variant Of", "Remove from Variant Group",
        ] {
            XCTAssertTrue(screenMenu.items.contains { $0.title == title }, "Screen > \(title) is missing")
        }
        let kinds = try XCTUnwrap(screenMenu.items.first { $0.title == "Kind" }?.submenu)
        XCTAssertEqual(kinds.items.map(\.title), ["Screen", "Modal", "Sheet", "Popover", "Menu", "Alert"])

        let goMenu = try XCTUnwrap(mainMenu.items.first { $0.title == "Go" }?.submenu)
        let expected: [(String, KeyCombo)] = [
            ("Back", KeyCombo("left", [.command, .option])), ("Forward", KeyCombo("right", [.command, .option])),
            ("Follow Link", KeyCombo("l")), ("Next Screen", KeyCombo("down", [.command, .option])),
            ("Previous Screen", KeyCombo("up", [.command, .option])),
        ]
        for (title, combo) in expected {
            let item = try XCTUnwrap(goMenu.items.first { $0.title == title }, "Go > \(title) is missing")
            XCTAssertEqual(item.keyEquivalent, combo.menuKeyEquivalent.key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, combo.menuKeyEquivalent.modifiers, title)
        }
    }

    @MainActor
    func testScreenMenuItemsAreEnabledOnlyWhenTheyCanAct() throws {
        let (_, controller, screens) = try makeWindow()
        defer { controller.close() }
        func item(_ action: Selector, _ represented: Any? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.representedObject = represented
            return item
        }
        typealias Controller = DocumentWindowController
        XCTAssertTrue(controller.validateMenuItem(item(#selector(Controller.removeFromVariantGroup(_:)))))
        XCTAssertFalse(
            controller.validateMenuItem(item(#selector(Controller.showPreviousScreen(_:)))), "Login is first")
        XCTAssertTrue(controller.validateMenuItem(item(#selector(Controller.showNextScreen(_:)))))
        XCTAssertFalse(controller.validateMenuItem(item(#selector(Controller.followLink(_:)))), "nothing selected")

        let screenKind = item(#selector(Controller.setScreenKind(_:)), ScreenKind.screen.rawValue)
        XCTAssertTrue(controller.validateMenuItem(screenKind))
        XCTAssertEqual(screenKind.state, .on)

        let makeVariant = NSMenu()
        controller.populateMakeVariantMenu(makeVariant)
        XCTAssertEqual(
            makeVariant.items.map(\.title), ["Login (Desktop)", "Reset Password", "Settings", "Account Menu"])

        screens.showNextScreen()
        screens.showNextScreen()
        XCTAssertFalse(
            controller.validateMenuItem(item(#selector(Controller.removeFromVariantGroup(_:)))),
            "Reset Password isn't in a group")
    }
}
