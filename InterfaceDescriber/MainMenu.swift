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
        item.setKeyEquivalent(for: keybind, index: index)
        menu.addItem(item)
        return item
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
