import AppKit
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
}
