import AppKit
import DescriberCore
import SwiftUI

/// A document window: the screen sidebar on the left (hidden by default), the canvas in the middle, and the details
/// panel on the right, shown while a region is open in it.
final class DocumentWindowController: NSWindowController {
    /// How long the details panel takes to slide in or out. Nothing animates while the window is off screen.
    static let detailsAnimationDuration = 0.25

    let splitViewController = NSSplitViewController()
    let canvasController: CanvasViewController
    let detailsController: DetailsPanelController
    let screenController: ScreenController
    /// The region editor the details panel shows, to tell opening from switching. Held strongly, so a new editor
    /// can't reuse its address and look like the same one.
    private var shownDetails: RegionEditor?

    init(model: DocumentModel) {
        canvasController = CanvasViewController(model: model)
        detailsController = DetailsPanelController(model: model)
        screenController = ScreenController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)

        let sidebar = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(
                rootView: ScreenSidebar(model: model, controller: screenController))
        )
        sidebar.isCollapsed = true
        sidebar.minimumThickness = 180

        let canvas = NSSplitViewItem(viewController: canvasController)

        let inspector = NSSplitViewItem(inspectorWithViewController: detailsController)
        inspector.isCollapsed = true
        inspector.minimumThickness = 260
        inspector.canCollapse = true

        splitViewController.addSplitViewItem(sidebar)
        splitViewController.addSplitViewItem(canvas)
        splitViewController.addSplitViewItem(inspector)

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        window.delegate = self

        model.detailsDidChange = { [weak self] in
            self?.updateDetails()
        }
        detailsController.onClose = { [weak model] in
            model?.closeDetails()
        }
        screenController.window = window
        screenController.anchorView = canvasController.canvasView
        canvasController.followLinks = { [weak self] region, anchor in
            self?.screenController.followLinks(of: region, at: anchor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var sidebarItem: NSSplitViewItem {
        splitViewController.splitViewItems[0]
    }

    var canvasItem: NSSplitViewItem {
        splitViewController.splitViewItems[1]
    }

    var inspectorItem: NSSplitViewItem {
        splitViewController.splitViewItems[2]
    }

    // MARK: Zoom
    // Here rather than on the canvas so the View menu reaches them whichever pane has focus.

    @objc func zoomIn(_ sender: Any?) {
        canvasController.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        canvasController.zoomOut()
    }

    @objc func actualSize(_ sender: Any?) {
        canvasController.actualSize()
    }

    // MARK: Tools

    @objc func chooseSelectTool(_ sender: Any?) {
        canvasController.choose(.select)
    }

    @objc func chooseRegionTool(_ sender: Any?) {
        canvasController.choose(.region)
    }

    @objc func chooseWriteTool(_ sender: Any?) {
        canvasController.choose(.write)
    }

    @objc func toggleSnapping(_ sender: Any?) {
        canvasController.toggleSnapping()
    }

    @objc func showGridSize(_ sender: Any?) {
        canvasController.toggleGridSizePopover()
    }

    // MARK: Selection and editing
    // Copy, Paste and Select All use the standard selectors, so a text view being edited takes them first. Delete has
    // its own, since a text view would take the bare Delete key as a menu command.

    @objc func copy(_ sender: Any?) {
        canvasController.copySelection()
    }

    @objc func paste(_ sender: Any?) {
        canvasController.paste()
    }

    override func selectAll(_ sender: Any?) {
        canvasController.selectAll()
    }

    @objc func duplicateSelection(_ sender: Any?) {
        canvasController.duplicate()
    }

    @objc func deleteSelection(_ sender: Any?) {
        canvasController.deleteSelection()
    }

    @objc func selectParent(_ sender: Any?) {
        canvasController.selectParent()
    }

    @objc func selectChildren(_ sender: Any?) {
        canvasController.selectChildren()
    }

    @objc func bringToFront(_ sender: Any?) {
        canvasController.reorderSelection(to: .front)
    }

    @objc func sendToBack(_ sender: Any?) {
        canvasController.reorderSelection(to: .back)
    }

    /// The Nudge menu's items carry their `KeyAction` as the represented object.
    @objc func nudge(_ sender: Any?) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String, let action = KeyAction(rawValue: name)
        else { return }
        canvasController.nudge(action)
    }

    @objc func toggleDescription(_ sender: Any?) {
        canvasController.toggleDescriptions(all: false)
    }

    @objc func toggleAllDescriptions(_ sender: Any?) {
        canvasController.toggleDescriptions(all: true)
    }

    // MARK: Screens (spec 8.1 to 8.3)
    // Each acts on the active screen. Items that pick a kind, viewport or screen carry it as the represented object.

    private var activeScreen: Screen? {
        canvasController.model.activeScreen
    }

    @objc func newScreen(_ sender: Any?) {
        screenController.newScreen()
    }

    @objc func duplicateScreen(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.duplicateScreen(screen.id)
    }

    @objc func renameScreen(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.promptRename(screen.id)
    }

    @objc func deleteScreen(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.deleteScreen(screen.id)
    }

    @objc func setScreenKind(_ sender: Any?) {
        guard let screen = activeScreen, let name = (sender as? NSMenuItem)?.representedObject as? String,
            let kind = ScreenKind(rawValue: name)
        else { return }
        screenController.setKind(kind, of: screen.id)
    }

    @objc func setScreenViewport(_ sender: Any?) {
        guard let screen = activeScreen,
            let viewport = ((sender as? NSMenuItem)?.representedObject as? ViewportBox)?.viewport
        else { return }
        screenController.setViewport(viewport, of: screen.id)
    }

    @objc func useThisDevice(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.useThisDevice(for: screen.id)
    }

    @objc func chooseCustomViewport(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.chooseCustomSize(for: screen.id)
    }

    @objc func refreshThisDevice(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.refreshThisDevice(for: screen.id)
    }

    @objc func saveViewportPreset(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.saveViewportAsPreset(for: screen.id)
    }

    /// The New Variant items carry a viewport, or none for This Device, measured when chosen.
    @objc func newVariant(_ sender: Any?) {
        guard let screen = activeScreen, let item = sender as? NSMenuItem else { return }
        let viewport = (item.representedObject as? ViewportBox)?.viewport ?? screenController.thisDeviceViewport
        guard let viewport else { return }
        screenController.newVariant(of: screen.id, viewport: viewport)
    }

    @objc func makeVariant(_ sender: Any?) {
        guard let screen = activeScreen, let target = (sender as? NSMenuItem)?.representedObject as? String else {
            return
        }
        screenController.makeVariant(screen.id, of: ScreenID(target))
    }

    @objc func removeFromVariantGroup(_ sender: Any?) {
        guard let screen = activeScreen else { return }
        screenController.removeFromVariantGroup(screen.id)
    }

    /// Fills the Viewport submenu: the presets, then This Device, Custom Size, Refresh and Save as Preset.
    func populateViewportMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        addViewportItems(to: menu, action: #selector(setScreenViewport(_:)))
        menu.addItem(NSMenuItem(title: "This Device", action: #selector(useThisDevice(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Custom Size…", action: #selector(chooseCustomViewport(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Refresh to Current Display", action: #selector(refreshThisDevice(_:)), keyEquivalent: "")
        )
        menu.addItem(
            NSMenuItem(title: "Save Viewport as Preset…", action: #selector(saveViewportPreset(_:)), keyEquivalent: ""))
    }

    /// Fills the New Variant submenu with the presets and This Device.
    func populateNewVariantMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        addViewportItems(to: menu, action: #selector(newVariant(_:)))
        menu.addItem(NSMenuItem(title: "This Device", action: #selector(newVariant(_:)), keyEquivalent: ""))
    }

    /// The built-in presets, then the user's, each followed by a separator.
    private func addViewportItems(to menu: NSMenu, action: Selector) {
        let presets = screenController.presets
        for group in [presets.builtIn, presets.user] where !group.isEmpty {
            for preset in group {
                let item = NSMenuItem(title: ViewportPresets.menuTitle(for: preset), action: action, keyEquivalent: "")
                item.representedObject = ViewportBox(preset.viewport)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
    }

    /// Fills the Make Variant Of submenu with the other screens, in sidebar order.
    func populateMakeVariantMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let project = canvasController.model.project
        for id in SidebarOutline(project: project).screens where id != activeScreen?.id {
            guard let screen = project.screen(withID: id) else { continue }
            let item = NSMenuItem(title: screen.name, action: #selector(makeVariant(_:)), keyEquivalent: "")
            item.representedObject = id.rawValue
            menu.addItem(item)
        }
    }

    // MARK: Following links and moving between screens (spec 8.4 and Section 9)

    @objc func goBack(_ sender: Any?) {
        screenController.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        screenController.goForward()
    }

    @objc func followLink(_ sender: Any?) {
        canvasController.followSelectedLink()
    }

    @objc func showNextScreen(_ sender: Any?) {
        screenController.showNextScreen()
    }

    @objc func showPreviousScreen(_ sender: Any?) {
        screenController.showPreviousScreen()
    }

    // MARK: Details panel

    var isShowingDetails: Bool {
        !inspectorItem.isCollapsed
    }

    /// Shows the region open in the model's details panel: slides the panel in and fits the canvas to the region when
    /// it opens, refits when it switches regions, and slides it out and restores the canvas when it closes.
    func updateDetails() {
        let editor = canvasController.model.details
        guard editor !== shownDetails else { return }
        let wasOpen = shownDetails != nil
        shownDetails = editor
        let animated = window?.isVisible == true

        if let editor {
            detailsController.load()
            if !wasOpen {
                canvasController.prepareForDetails()
                let canvasWidth = canvasController.canvasView.bounds.width
                setDetailsCollapsed(false, animated: animated) { [weak self] in
                    self?.refitDetails()
                }
                // While the panel slides in, aim for the width the canvas will have.
                let predicted = animated ? canvasWidth - panelThickness : canvasController.canvasView.bounds.width
                canvasController.fitForDetails(editor.region, canvasWidth: predicted)
            } else {
                canvasController.fitForDetails(editor.region, canvasWidth: canvasController.canvasView.bounds.width)
            }
            window?.makeFirstResponder(detailsController.titleField)
        } else {
            detailsController.textUndoManager.removeAllActions()
            if detailsController.isEditingText(window?.firstResponder) || window?.firstResponder === window {
                window?.makeFirstResponder(canvasController.canvasView)
            }
            setDetailsCollapsed(true, animated: animated, completion: nil)
            canvasController.restoreAfterDetails()
        }
    }

    /// The width the details panel takes from the canvas when it opens.
    private var panelThickness: CGFloat {
        let width = detailsController.view.frame.width
        return max(width > 0 ? width : DetailsPanelController.width, inspectorItem.minimumThickness)
            + splitViewController.splitView.dividerThickness
    }

    private func setDetailsCollapsed(_ collapsed: Bool, animated: Bool, completion: (() -> Void)?) {
        guard inspectorItem.isCollapsed != collapsed else {
            completion?()
            return
        }
        guard animated else {
            inspectorItem.isCollapsed = collapsed
            splitViewController.splitView.layoutSubtreeIfNeeded()
            completion?()
            return
        }
        let item = inspectorItem
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.detailsAnimationDuration
            context.allowsImplicitAnimation = true
            MainActor.assumeIsolated {
                item.animator().isCollapsed = collapsed
            }
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }

    /// Fits the open region again once the panel has its final width, in case the guess was off.
    private func refitDetails() {
        guard let editor = canvasController.model.details else { return }
        canvasController.fitForDetails(editor.region, canvasWidth: canvasController.canvasView.bounds.width)
        if window?.firstResponder === window || window?.firstResponder === canvasController.canvasView {
            window?.makeFirstResponder(detailsController.titleField)
        }
    }

    /// Whether a text field in the window is being edited, which turns off the canvas and tool keybinds (spec 6.3).
    var isEditingText: Bool {
        window?.firstResponder is NSText
    }

    /// Whether keys go to the canvas: it has focus, or nothing in the window does. Canvas keys without Cmd only work
    /// then, so they never take keys from the panel's fields and pop-ups or the sidebar.
    var canvasHasFocus: Bool {
        guard let window else { return false }
        return window.firstResponder === canvasController.canvasView || window.firstResponder === window
    }
}

extension DocumentWindowController: NSWindowDelegate {
    /// The details panel's fields get its own field editor, so Cmd-Z while typing undoes typing there rather than
    /// document steps.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if let view = client as? NSView, detailsController.isViewLoaded, view.isDescendant(of: detailsController.view) {
            return detailsController.fieldEditor
        }
        return nil
    }
}

extension DocumentWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let model = canvasController.model
        switch menuItem.action {
        case #selector(chooseSelectTool(_:)):
            menuItem.state = model.tool == .select ? .on : .off
        case #selector(chooseRegionTool(_:)):
            menuItem.state = model.tool == .region ? .on : .off
        case #selector(chooseWriteTool(_:)):
            menuItem.state = model.tool == .write ? .on : .off
        case #selector(toggleSnapping(_:)):
            menuItem.state = model.snappingEnabled ? .on : .off
        case #selector(showGridSize(_:)):
            break
        case #selector(copy(_:)), #selector(duplicateSelection(_:)), #selector(bringToFront(_:)),
            #selector(sendToBack(_:)):
            return !isEditingText && canvasController.hasSelection
        case #selector(paste(_:)):
            return !isEditingText && canvasController.canPaste
        case #selector(selectAll(_:)), #selector(toggleAllDescriptions(_:)):
            let hasRegions = model.activeScreen.map { !$0.regions.isEmpty } ?? false
            return hasRegions && (menuItem.action == #selector(selectAll(_:)) || canvasHasFocus)
        case #selector(deleteSelection(_:)), #selector(selectParent(_:)), #selector(selectChildren(_:)),
            #selector(nudge(_:)), #selector(toggleDescription(_:)):
            return canvasHasFocus && canvasController.hasSelection
        case #selector(newScreen(_:)):
            break
        case #selector(duplicateScreen(_:)), #selector(renameScreen(_:)), #selector(chooseCustomViewport(_:)),
            #selector(saveViewportPreset(_:)), #selector(newVariant(_:)), #selector(makeVariant(_:)):
            return activeScreen != nil
        case #selector(deleteScreen(_:)):
            return activeScreen.map { screenController.canDelete($0.id) } ?? false
        case #selector(setScreenKind(_:)):
            let kind = (menuItem.representedObject as? String).flatMap(ScreenKind.init(rawValue:))
            menuItem.state = activeScreen != nil && activeScreen?.kind == kind ? .on : .off
            return activeScreen != nil
        case #selector(setScreenViewport(_:)):
            let viewport = (menuItem.representedObject as? ViewportBox)?.viewport
            menuItem.state = activeScreen != nil && activeScreen?.viewport == viewport ? .on : .off
            return activeScreen != nil
        case #selector(useThisDevice(_:)):
            let isThisDevice = activeScreen?.viewport.preset == ViewportPresets.thisDeviceID
            menuItem.state = isThisDevice ? .on : .off
            return activeScreen != nil
        case #selector(refreshThisDevice(_:)):
            return activeScreen?.viewport.preset == ViewportPresets.thisDeviceID
        case #selector(removeFromVariantGroup(_:)):
            return activeScreen.map { screenController.isInVariantGroup($0.id) } ?? false
        case #selector(goBack(_:)):
            return !isEditingText && screenController.canGoBack
        case #selector(goForward(_:)):
            return !isEditingText && screenController.canGoForward
        case #selector(showNextScreen(_:)):
            return !isEditingText && screenController.neighbor(offset: 1) != nil
        case #selector(showPreviousScreen(_:)):
            return !isEditingText && screenController.neighbor(offset: -1) != nil
        case #selector(followLink(_:)):
            return canvasHasFocus && canvasController.canFollowLink
        default:
            return true
        }
        // A bare-key equivalent such as R would otherwise take the key from the text being typed.
        return !(isEditingText && menuItem.keyEquivalentModifierMask.isDisjoint(with: [.command, .control]))
    }
}

/// A viewport as a menu item's represented object.
final class ViewportBox: NSObject {
    let viewport: Viewport

    init(_ viewport: Viewport) {
        self.viewport = viewport
    }
}
