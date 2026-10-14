import AppKit

/// The document window's split view: sidebar, canvas and details panel. It handles Toggle Sidebar, a registry
/// keybind, so it asks the window controller whether keybind items may run, which they may not while a field is being
/// edited (spec 6.3).
final class DocumentSplitViewController: NSSplitViewController {
    /// Answers whether a menu item may run as far as text editing goes. The window controller sets it.
    var allowsKeybindItem: ((NSMenuItem) -> Bool)?

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = item as? NSMenuItem, allowsKeybindItem?(menuItem) == false {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }
}
