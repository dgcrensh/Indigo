import AppKit
import DescriberCore
import SwiftUI

/// A document window: the screen sidebar on the left (hidden by default), the canvas in the middle, and a slot on
/// the right for the details panel (milestone 6).
final class DocumentWindowController: NSWindowController {
    let splitViewController = NSSplitViewController()
    let canvasController: CanvasViewController

    init(model: DocumentModel) {
        canvasController = CanvasViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)

        let sidebar = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: ScreenSidebar(model: model))
        )
        sidebar.isCollapsed = true
        sidebar.minimumThickness = 180

        let canvas = NSSplitViewItem(viewController: canvasController)

        let inspector = NSSplitViewItem(inspectorWithViewController: NSHostingController(rootView: Color.clear))
        inspector.isCollapsed = true
        inspector.minimumThickness = 260

        splitViewController.addSplitViewItem(sidebar)
        splitViewController.addSplitViewItem(canvas)
        splitViewController.addSplitViewItem(inspector)

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
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

    /// Whether a text field in the window is being edited, which turns off the canvas and tool keybinds (spec 6.3).
    var isEditingText: Bool {
        window?.firstResponder is NSText
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
        default:
            return true
        }
        // A bare-key equivalent such as R would otherwise take the key from the text being typed.
        return !(isEditingText && menuItem.keyEquivalentModifierMask.isDisjoint(with: [.command, .control]))
    }
}
