import AppKit
import DescriberCore
import XCTest

@testable import InterfaceDescriber

/// `settings.json` read, watched and applied to open windows and the menu bar (spec 3 and 12), with a store on a
/// temporary file.
final class SettingsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private var settingsURL: URL {
        temporaryDirectory.appendingPathComponent("settings.json")
    }

    private func write(_ text: String, atomically: Bool = true) throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settingsURL, options: atomically ? .atomic : [])
    }

    /// A window on a new document following `store`.
    @MainActor
    private func makeWindow(
        _ store: SettingsStore
    ) throws -> (Document, DocumentWindowController, CanvasViewController) {
        let document = Document()
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.settingsStore = store
        controller.window?.layoutIfNeeded()
        document.undoManager?.groupsByEvent = false
        controller.canvasController.update()
        return (document, controller, controller.canvasController)
    }

    /// Waits for `store` to post a change, as its watcher does after the file changes.
    @MainActor
    private func waitForChange(of store: SettingsStore, _ body: () throws -> Void) rethrows {
        let changed = expectation(forNotification: SettingsStore.didChangeNotification, object: store)
        try body()
        wait(for: [changed], timeout: 5)
    }

    // MARK: Reading

    @MainActor
    func testAHandEditAppliesWhenTheFileIsReadAgain() throws {
        let store = SettingsStore(url: settingsURL)
        XCTAssertEqual(store.settings, .defaults, "no file is the defaults")
        XCTAssertNil(store.error)
        try write(#"{"gridSize": 16, "viewportPresets": [{"name": "Watch", "width": 198, "height": 242}]}"#)
        store.reload()
        XCTAssertEqual(store.settings.gridSize, 16)
        XCTAssertEqual(store.settings.viewportPresets.map(\.name), ["Watch"])
        XCTAssertNil(store.error)
    }

    @MainActor
    func testABadFileKeepsTheSettingsAndIsNeverWritten() throws {
        try write(#"{"gridSize": 16, "keybinds": {"regionTool": "b"}}"#)
        let store = SettingsStore(url: settingsURL)
        let bad = #"{"gridSize": 16, "keybinds": {"regionTool": "hyper-b"}}"#
        try write(bad)
        store.reload()
        XCTAssertEqual(store.settings.gridSize, 16)
        XCTAssertEqual(store.settings.keybinds.action(for: KeyCombo("b")), .regionTool, "the keybinds from before")
        XCTAssertEqual(
            store.error?.localizedDescription,
            "settings.json: keybinds.regionTool has “hyper-b”, which isn’t a key. Keys look like “v”, “shift-d” or "
                + "“cmd-option-left”.")

        XCTAssertThrowsError(try store.save(name: "Watch", width: 198, height: 242), "saving a preset refuses")
        XCTAssertEqual(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self), bad)
        XCTAssertEqual(store.settings.viewportPresets, [])
    }

    @MainActor
    func testARemovedFileGoesBackToTheDefaults() throws {
        try write(#"{"gridSize": 16}"#)
        let store = SettingsStore(url: settingsURL)
        XCTAssertEqual(store.settings.gridSize, 16)
        try FileManager.default.removeItem(at: settingsURL)
        store.reload()
        XCTAssertEqual(store.settings, .defaults)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testSettingsCreatesAnEmptyFileOnlyWhenThereIsNone() throws {
        let store = SettingsStore(url: settingsURL)
        try store.createFileIfMissing()
        XCTAssertEqual(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self), "{}\n")
        XCTAssertNil(store.error)

        let existing = #"{"gridSize": 16}"#
        try write(existing)
        try store.createFileIfMissing()
        XCTAssertEqual(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self), existing)
    }

    // MARK: Watching

    @MainActor
    func testTheWatcherAppliesAnAtomicReplace() throws {
        let store = SettingsStore(url: settingsURL)
        store.startWatching()
        defer { store.stopWatching() }
        try waitForChange(of: store) { try write(#"{"gridSize": 16}"#) }
        XCTAssertEqual(store.settings.gridSize, 16)
        // The replaced file is watched too, and replacing it again is seen.
        try waitForChange(of: store) { try write(#"{"gridSize": 24}"#) }
        XCTAssertEqual(store.settings.gridSize, 24)
    }

    @MainActor
    func testTheWatcherAppliesAWriteInPlace() throws {
        try write(#"{"gridSize": 16}"#)
        let store = SettingsStore(url: settingsURL)
        store.startWatching()
        defer { store.stopWatching() }
        try waitForChange(of: store) { try write(#"{"gridSize": 32}"#, atomically: false) }
        XCTAssertEqual(store.settings.gridSize, 32)
        try waitForChange(of: store) { try write("{ oops", atomically: false) }
        XCTAssertEqual(store.settings.gridSize, 32)
        XCTAssertNotNil(store.error)
    }

    // MARK: Applying

    @MainActor
    func testAKeybindOverrideChangesTheMenuAndTheCanvasKeys() throws {
        let store = SettingsStore(url: settingsURL)
        let (document, controller, canvas) = try makeWindow(store)
        defer { controller.close() }
        try write(#"{"keybinds": {"regionTool": "b", "followLink": []}}"#)
        store.reload()

        XCTAssertTrue(canvas.canvasKeyDown(KeyCombo("b")))
        XCTAssertEqual(document.model.tool, .region)
        XCTAssertEqual(canvas.toastView.text, "Region tool — B")
        canvas.choose(.select)
        XCTAssertFalse(canvas.canvasKeyDown(KeyCombo("r")), "R no longer picks the Region tool")
        XCTAssertEqual(document.model.tool, .select)

        let menu = MainMenu.make()
        MainMenu.applyKeybinds(store.settings.keybinds, to: menu)
        let tools = try XCTUnwrap(menu.items.first { $0.title == "Tools" }?.submenu)
        XCTAssertEqual(tools.items.first { $0.title == "Region Tool" }?.keyEquivalent, "b")
        XCTAssertEqual(tools.items.first { $0.title == "Select Tool" }?.keyEquivalent, "v")
        let go = try XCTUnwrap(menu.items.first { $0.title == "Go" }?.submenu)
        XCTAssertEqual(go.items.first { $0.title == "Follow Link" }?.keyEquivalent, "", "an empty list unbinds")

        MainMenu.applyKeybinds(.defaults, to: menu)
        XCTAssertEqual(tools.items.first { $0.title == "Region Tool" }?.keyEquivalent, "r")
    }

    @MainActor
    func testABadFileShowsTheBannerAndKeepsTheKeysUntilItIsFixed() throws {
        try write(#"{"keybinds": {"regionTool": "b"}}"#)
        let store = SettingsStore(url: settingsURL)
        let (document, controller, canvas) = try makeWindow(store)
        defer { controller.close() }
        let banner = canvas.settingsBanner
        XCTAssertTrue(banner.isHidden)

        try write(#"{"keybinds": {"regionTool": "b"},}"#)
        store.reload()
        XCTAssertFalse(banner.isHidden)
        let message = try XCTUnwrap(banner.message)
        XCTAssertTrue(message.hasPrefix("settings.json: line 1"), message)
        XCTAssertTrue(banner.messageLabel.stringValue.hasSuffix(SettingsBanner.note))
        XCTAssertTrue(canvas.canvasKeyDown(KeyCombo("b")), "the keys from before still work")
        XCTAssertEqual(document.model.tool, .region)

        banner.dismiss(nil)
        XCTAssertTrue(banner.isHidden)
        try write(#"{"gridSize": "8"}"#)
        store.reload()
        XCTAssertFalse(banner.isHidden, "a new error shows again")

        try write(#"{"keybinds": {"regionTool": "n"}}"#)
        store.reload()
        XCTAssertTrue(banner.isHidden)
        XCTAssertNil(banner.message)
        XCTAssertEqual(document.model.keybinds.action(for: KeyCombo("n")), .regionTool)
    }

    @MainActor
    func testTheGridDefaultAppliesToAnOpenWindow() throws {
        let store = SettingsStore(url: settingsURL)
        let (_, controller, canvas) = try makeWindow(store)
        defer { controller.close() }
        XCTAssertEqual(canvas.canvasView.gridSize, Snapping.defaultGridSize)
        try write(#"{"gridSize": 24}"#)
        store.reload()
        canvas.update()
        XCTAssertEqual(canvas.canvasView.gridSize, 24)
        let screen = try XCTUnwrap(controller.canvasController.model.activeScreen)
        XCTAssertEqual(canvas.gridSize(for: screen), 24, "snapping uses it too")
    }

    @MainActor
    func testTheDefaultViewportAppliesToNewScreens() throws {
        let store = SettingsStore(url: settingsURL)
        let (document, controller, _) = try makeWindow(store)
        defer { controller.close() }
        try write(#"{"defaultViewport": "ipad"}"#)
        store.reload()
        document.undoManager?.beginUndoGrouping()
        controller.screenController.newScreen()
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(document.model.activeScreen?.viewport, Viewport(preset: "ipad", width: 820, height: 1180))

        try write(#"{"defaultViewport": "this-device"}"#)
        store.reload()
        controller.screenController.displaySize = { CGSize(width: 1512, height: 982) }
        document.undoManager?.beginUndoGrouping()
        controller.screenController.newScreen()
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(
            document.model.activeScreen?.viewport,
            Viewport(preset: ViewportPresets.thisDeviceID, width: 1512, height: 982))
    }

    @MainActor
    func testTheSnappingDefaultAppliesToNewWindowsOnly() throws {
        let store = SettingsStore(url: settingsURL)
        let (document, controller, _) = try makeWindow(store)
        defer { controller.close() }
        XCTAssertTrue(document.model.snappingEnabled)
        try write(#"{"snapping": false}"#)
        store.reload()
        XCTAssertTrue(document.model.snappingEnabled, "an open window keeps its snapping")

        let model = DocumentModel(project: .untitled())
        let newWindow = DocumentWindowController(model: model, settingsStore: store)
        defer { newWindow.close() }
        XCTAssertFalse(model.snappingEnabled)
    }
}
