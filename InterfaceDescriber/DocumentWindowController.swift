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
    /// The region editor the details panel shows, to tell opening from switching.
    private var shownDetails: ObjectIdentifier?

    init(model: DocumentModel) {
        canvasController = CanvasViewController(model: model)
        detailsController = DetailsPanelController(model: model)
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

    // MARK: Details panel

    var isShowingDetails: Bool {
        !inspectorItem.isCollapsed
    }

    /// Shows the region open in the model's details panel: slides the panel in and fits the canvas to the region when
    /// it opens, refits when it switches regions, and slides it out and restores the canvas when it closes.
    func updateDetails() {
        let editor = canvasController.model.details
        let shown = editor.map(ObjectIdentifier.init)
        guard shown != shownDetails else { return }
        let wasOpen = shownDetails != nil
        shownDetails = shown
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
}

extension DocumentWindowController: NSWindowDelegate {
    /// While a details panel field is being edited, Cmd-Z undoes typing there rather than document steps.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        if detailsController.isEditingText(window.firstResponder) {
            return detailsController.textUndoManager
        }
        return (document as? NSDocument)?.undoManager
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
