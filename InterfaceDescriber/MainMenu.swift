import AppKit
import DescriberCore

/// Builds the menu bar in code, since the app has no storyboard or nib. Each milestone adds the items for the
/// features it ships; this skeleton has only the items that work now.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(fileMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(viewMenu()))
        mainMenu.addItem(submenuItem(screenMenu()))
        mainMenu.addItem(submenuItem(goMenu()))
        mainMenu.addItem(submenuItem(toolsMenu()))
        let windowMenu = windowMenu()
        mainMenu.addItem(submenuItem(windowMenu))
        NSApplication.shared.windowsMenu = windowMenu
        #if DEBUG
            mainMenu.addItem(submenuItem(debugMenu()))
        #endif
        let helpMenu = NSMenu(title: "Help")
        mainMenu.addItem(submenuItem(helpMenu))
        NSApplication.shared.helpMenu = helpMenu
        return mainMenu
    }

    /// An item whose key equivalent comes from the keybind registry. `index` picks one of the action's combinations.
    @discardableResult
    private static func addItem(
        to menu: NSMenu, _ title: String, action: Selector, keybind: KeyAction, index: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("\(keybindPrefix)\(keybind.rawValue).\(index)")
        item.setKeyEquivalent(for: keybind, index: index)
        menu.addItem(item)
        return item
    }

    /// Starts the identifier of every item whose key comes from the registry, followed by its action and index.
    private static let keybindPrefix = "keybind."

    /// The keybind action and combination index of an item `addItem` made, or nil for any other item.
    static func keybind(of item: NSMenuItem) -> (action: KeyAction, index: Int)? {
        guard let identifier = item.identifier?.rawValue, identifier.hasPrefix(keybindPrefix) else { return nil }
        let parts = identifier.dropFirst(keybindPrefix.count).split(separator: ".")
        guard parts.count == 2, let action = KeyAction(rawValue: String(parts[0])), let index = Int(parts[1]) else {
            return nil
        }
        return (action, index)
    }

    /// Sets the key equivalent of every item in `menu` and its submenus whose key comes from the registry, after the
    /// keybinds in settings change.
    static func applyKeybinds(_ registry: KeybindRegistry, to menu: NSMenu) {
        for item in menu.items {
            if let keybind = keybind(of: item) {
                item.setKeyEquivalent(for: keybind.action, in: registry, index: keybind.index)
            }
            if let submenu = item.submenu {
                applyKeybinds(registry, to: submenu)
            }
        }
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = AppIdentity.appName
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: "About \(name)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(
            withTitle: "Open…",
            action: #selector(NSDocumentController.openDocument(_:)),
            keyEquivalent: "o"
        )
        menu.addItem(submenuItem(openRecentMenu()))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let duplicate = menu.addItem(
            withTitle: "Duplicate",
            action: #selector(NSDocument.duplicate(_:)),
            keyEquivalent: "s"
        )
        duplicate.keyEquivalentModifierMask = [.command, .shift]
        let saveAs = menu.addItem(
            withTitle: "Save As…",
            action: #selector(NSDocument.saveAs(_:)),
            keyEquivalent: "s"
        )
        saveAs.keyEquivalentModifierMask = [.command, .shift, .option]
        menu.addItem(
            withTitle: "Revert to Saved",
            action: #selector(NSDocument.revertToSaved(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(submenuItem(exportMenu()))
        return menu
    }

    /// The exports in spec Section 11.
    private static func exportMenu() -> NSMenu {
        let menu = NSMenu(title: "Export")
        menu.addItem(
            withTitle: "Markdown…", action: #selector(DocumentWindowController.exportMarkdown(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Single-File JSON…", action: #selector(DocumentWindowController.exportJSON(_:)),
            keyEquivalent: "")
        menu.addItem(
            withTitle: "PNG Images…", action: #selector(DocumentWindowController.exportPNGs(_:)), keyEquivalent: "")
        return menu
    }

    /// `NSDocumentController` finds this menu by its Clear Menu item and fills it with recent documents.
    private static func openRecentMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        menu.addItem(
            withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        addItem(to: menu, "Undo", action: Selector(("undo:")), keybind: .undo)
        addItem(to: menu, "Redo", action: Selector(("redo:")), keybind: .redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        addItem(to: menu, "Copy", action: #selector(NSText.copy(_:)), keybind: .copy)
        addItem(to: menu, "Paste", action: #selector(NSText.paste(_:)), keybind: .paste)
        addItem(
            to: menu, "Duplicate", action: #selector(DocumentWindowController.duplicateSelection(_:)),
            keybind: .duplicate)
        addItem(to: menu, "Delete", action: #selector(DocumentWindowController.deleteSelection(_:)), keybind: .delete)
        // Forward Delete deletes too.
        let forwardDelete = addItem(
            to: menu, "Delete", action: #selector(DocumentWindowController.deleteSelection(_:)), keybind: .delete,
            index: 1)
        forwardDelete.isHidden = true
        forwardDelete.allowsKeyEquivalentWhenHidden = true
        addItem(to: menu, "Select All", action: #selector(NSText.selectAll(_:)), keybind: .selectAll)
        menu.addItem(.separator())
        addItem(
            to: menu, "Select Parent", action: #selector(DocumentWindowController.selectParent(_:)),
            keybind: .selectParent)
        addItem(
            to: menu, "Select Children", action: #selector(DocumentWindowController.selectChildren(_:)),
            keybind: .selectChildren)
        menu.addItem(.separator())
        addItem(
            to: menu, "Bring to Front", action: #selector(DocumentWindowController.bringToFront(_:)),
            keybind: .bringToFront)
        addItem(
            to: menu, "Send to Back", action: #selector(DocumentWindowController.sendToBack(_:)),
            keybind: .sendToBack)
        menu.addItem(submenuItem(nudgeMenu()))
        return menu
    }

    /// The arrow-key nudges (spec Section 7). Each item carries its action, so one method handles them all.
    private static func nudgeMenu() -> NSMenu {
        let menu = NSMenu(title: "Nudge")
        let items: [(String, KeyAction)] = [
            ("Nudge Left", .nudgeLeft), ("Nudge Right", .nudgeRight), ("Nudge Up", .nudgeUp),
            ("Nudge Down", .nudgeDown), ("Nudge Left Four Steps", .nudgeLeftFar),
            ("Nudge Right Four Steps", .nudgeRightFar), ("Nudge Up Four Steps", .nudgeUpFar),
            ("Nudge Down Four Steps", .nudgeDownFar),
        ]
        for (index, (title, action)) in items.enumerated() {
            if index == 4 { menu.addItem(.separator()) }
            let item = addItem(to: menu, title, action: #selector(DocumentWindowController.nudge(_:)), keybind: action)
            item.representedObject = action.rawValue
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        addItem(to: menu, "Zoom In", action: #selector(DocumentWindowController.zoomIn(_:)), keybind: .zoomIn)
        // Cmd = is the same key as Cmd + without Shift, so it zooms in too.
        let zoomInEquals = addItem(
            to: menu, "Zoom In", action: #selector(DocumentWindowController.zoomIn(_:)), keybind: .zoomIn, index: 1)
        zoomInEquals.isHidden = true
        zoomInEquals.allowsKeyEquivalentWhenHidden = true
        addItem(to: menu, "Zoom Out", action: #selector(DocumentWindowController.zoomOut(_:)), keybind: .zoomOut)
        addItem(
            to: menu, "Actual Size", action: #selector(DocumentWindowController.actualSize(_:)), keybind: .actualSize)
        menu.addItem(.separator())
        addItem(
            to: menu, "Toggle Description", action: #selector(DocumentWindowController.toggleDescription(_:)),
            keybind: .toggleDescription)
        addItem(
            to: menu, "Toggle All Descriptions",
            action: #selector(DocumentWindowController.toggleAllDescriptions(_:)), keybind: .toggleAllDescriptions)
        menu.addItem(.separator())
        addItem(
            to: menu, "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keybind: .toggleSidebar)
        return menu
    }

    /// Screen management (spec 8.1 to 8.3). The Viewport, New Variant and Make Variant Of submenus are filled from
    /// the frontmost document window each time they open.
    private static func screenMenu() -> NSMenu {
        let menu = NSMenu(title: "Screen")
        typealias Controller = DocumentWindowController
        menu.addItem(withTitle: "New Screen", action: #selector(Controller.newScreen(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Duplicate Screen", action: #selector(Controller.duplicateScreen(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rename Screen…", action: #selector(Controller.renameScreen(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Delete Screen…", action: #selector(Controller.deleteScreen(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let kinds = NSMenu(title: "Kind")
        for kind in ScreenKind.allCases {
            let item = kinds.addItem(
                withTitle: kind.displayName, action: #selector(Controller.setScreenKind(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
        }
        menu.addItem(submenuItem(kinds))
        menu.addItem(submenuItem(dynamicMenu("Viewport") { $0.populateViewportMenu($1) }))
        menu.addItem(.separator())
        menu.addItem(submenuItem(dynamicMenu("New Variant") { $0.populateNewVariantMenu($1) }))
        menu.addItem(submenuItem(dynamicMenu("Make Variant Of") { $0.populateMakeVariantMenu($1) }))
        menu.addItem(
            withTitle: "Remove from Variant Group", action: #selector(Controller.removeFromVariantGroup(_:)),
            keyEquivalent: "")
        return menu
    }

    /// Link following and moving between screens (spec 8.4 and Section 9).
    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        typealias Controller = DocumentWindowController
        addItem(to: menu, "Back", action: #selector(Controller.goBack(_:)), keybind: .back)
        addItem(to: menu, "Forward", action: #selector(Controller.goForward(_:)), keybind: .forward)
        menu.addItem(.separator())
        addItem(to: menu, "Follow Link", action: #selector(Controller.followLink(_:)), keybind: .followLink)
        menu.addItem(.separator())
        addItem(to: menu, "Next Screen", action: #selector(Controller.showNextScreen(_:)), keybind: .nextScreen)
        addItem(
            to: menu, "Previous Screen", action: #selector(Controller.showPreviousScreen(_:)), keybind: .previousScreen)
        return menu
    }

    /// Keeps the delegates of the submenus filled when they open, since a menu holds its delegate weakly.
    private static var fillers: [DynamicMenuFiller] = []

    private static func dynamicMenu(
        _ title: String, fill: @escaping (DocumentWindowController, NSMenu) -> Void
    ) -> NSMenu {
        let menu = NSMenu(title: title)
        let filler = DynamicMenuFiller(fill: fill)
        fillers.append(filler)
        menu.delegate = filler
        return menu
    }

    /// The tools, snapping and the grid. Their keys have no modifiers, so the window controller turns them off while
    /// text is being edited.
    private static func toolsMenu() -> NSMenu {
        let menu = NSMenu(title: "Tools")
        addItem(
            to: menu, "Select Tool", action: #selector(DocumentWindowController.chooseSelectTool(_:)),
            keybind: .selectTool)
        addItem(
            to: menu, "Region Tool", action: #selector(DocumentWindowController.chooseRegionTool(_:)),
            keybind: .regionTool)
        addItem(
            to: menu, "Write Tool", action: #selector(DocumentWindowController.chooseWriteTool(_:)),
            keybind: .writeTool)
        menu.addItem(.separator())
        addItem(
            to: menu, "Snap to Grid", action: #selector(DocumentWindowController.toggleSnapping(_:)),
            keybind: .toggleSnapping)
        addItem(
            to: menu, "Grid Size…", action: #selector(DocumentWindowController.showGridSize(_:)), keybind: .gridSize)
        return menu
    }

    #if DEBUG
        /// Tools for checking the app by hand, in debug builds only.
        private static func debugMenu() -> NSMenu {
            let menu = NSMenu(title: "Debug")
            menu.addItem(
                withTitle: "New 500-Region Document",
                action: #selector(AppDelegate.newStressTestDocument(_:)),
                keyEquivalent: ""
            )
            return menu
        }
    #endif

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        return menu
    }
}

/// Fills a submenu from the frontmost document window just before it opens.
@MainActor
final class DynamicMenuFiller: NSObject, NSMenuDelegate {
    let fill: (DocumentWindowController, NSMenu) -> Void

    init(fill: @escaping (DocumentWindowController, NSMenu) -> Void) {
        self.fill = fill
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller = NSApp.mainWindow?.windowController as? DocumentWindowController else {
            menu.removeAllItems()
            return
        }
        fill(controller, menu)
    }
}
