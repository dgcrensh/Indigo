import AppKit
import DescriberCore

/// Screen management and link following for one document window (spec Section 8). The sidebar, the Screen and Go
/// menus, and the canvas call it; it performs each edit as one command and asks the user through replaceable
/// closures, so tests answer for the user.
@MainActor
final class ScreenController {
    let model: DocumentModel
    /// Performs a command as one undo step. The document sets this to `Document.perform(_:)`; without it, commands
    /// go straight to the edit session.
    var performCommand: ((Command) throws -> Void)?
    var presetStore = UserPresetStore.shared
    /// The window, for sheets and for the display This Device measures.
    weak var window: NSWindow?

    /// The logical size of the whole display the window is on, menu bar and Dock areas included (spec 8.2).
    lazy var displaySize: () -> CGSize? = { [weak self] in
        (self?.window?.screen ?? NSScreen.main)?.frame.size
    }
    /// Asks a yes-or-no question with `button` as the yes, such as the delete question.
    lazy var confirm: (_ message: String, _ button: String, _ completion: @escaping (Bool) -> Void) -> Void = {
        [weak self] message, button, completion in
        self?.runConfirm(message, button: button, completion: completion)
    }
    /// Asks for a name, starting from `initial`; nil when cancelled.
    lazy var askName: (_ title: String, _ initial: String, _ completion: @escaping (String?) -> Void) -> Void = {
        [weak self] title, initial, completion in
        self?.runAskName(title, initial: initial, completion: completion)
    }
    /// Asks for a custom width and height, starting from `current`; nil when cancelled.
    lazy var askSize: (_ current: Viewport, _ completion: @escaping ((width: Int, height: Int)?) -> Void) -> Void = {
        [weak self] current, completion in
        self?.runAskSize(current, completion: completion)
    }
    /// Picks one of several links to follow, with a menu at a point in `anchorView`; nil when dismissed.
    lazy var chooseLink:
        (_ targets: [LinkTarget], _ anchor: CGPoint, _ completion: @escaping (LinkTarget?) -> Void) -> Void = {
            [weak self] targets, anchor, completion in
            self?.runChooseLink(targets, at: anchor, completion: completion)
        }
    /// Shows an error, such as a settings file that can't be read.
    lazy var showError: (Error) -> Void = { [weak self] error in
        self?.runShowError(error)
    }
    /// The view a link menu is shown in; the canvas.
    weak var anchorView: NSView?

    init(model: DocumentModel) {
        self.model = model
    }

    private var project: Project {
        model.project
    }

    /// Performs `command` as one step, and returns whether it was applied. A command with nothing to do changes
    /// nothing quietly; any other failure beeps.
    @discardableResult
    private func apply(_ command: Command) -> Bool {
        do {
            if let performCommand {
                try performCommand(command)
            } else {
                model.closeDetails()
                try model.session.perform(command)
                model.noteChange()
            }
            return true
        } catch EditError.nothingToDo {
            return false
        } catch {
            NSSound.beep()
            return false
        }
    }

    // MARK: Screens (spec 8.1)

    /// Adds "Screen N" after the active screen (after its variant group, when it has one) and shows it.
    func newScreen() {
        let index = model.activeScreenID.flatMap { id in project.screens.firstIndex { $0.id == id } }
        let add = AddScreen(
            name: ScreenNames.newScreenName(in: project), viewport: .defaultForNewScreens,
            at: index.map { $0 + 1 })
        if apply(add) {
            model.show(add.screen.id)
        }
    }

    /// Duplicates a screen after itself (after its variant group, when it has one) and shows the copy.
    func duplicateScreen(_ id: ScreenID) {
        let duplicate = DuplicateScreen(id)
        if apply(duplicate) {
            model.show(duplicate.newID)
        }
    }

    /// Renames a screen. A blank or unchanged name changes nothing.
    func renameScreen(_ id: ScreenID, to name: String) {
        guard let name = ScreenNames.cleaned(name), let screen = project.screen(withID: id), screen.name != name
        else { return }
        apply(ScreenCommands.rename(id, to: name))
    }

    /// Asks for a new name, then renames the screen.
    func promptRename(_ id: ScreenID) {
        guard let screen = project.screen(withID: id) else { return }
        askName("Rename Screen", screen.name) { [weak self] name in
            guard let name else { return }
            self?.renameScreen(id, to: name)
        }
    }

    func canDelete(_ id: ScreenID) -> Bool {
        project.screen(withID: id) != nil && project.screens.count > 1
    }

    /// Deletes a screen as one step, asking first when regions on other screens link to it; their links go with it.
    func deleteScreen(_ id: ScreenID) {
        guard canDelete(id) else { return }
        model.closeDetails()
        guard let message = ScreenDeleteConfirmation.message(deleting: id, in: project) else {
            apply(DeleteScreen(id))
            return
        }
        confirm(message, "Delete") { [weak self] confirmed in
            guard confirmed else { return }
            self?.apply(DeleteScreen(id))
        }
    }

    /// Puts the screens in the order a sidebar drag of the rows at `rows` to row `destination` leaves.
    func moveRows(_ rows: [Int], to destination: Int) {
        let order = SidebarOutline(project: project).order(afterMoving: rows, to: destination)
        apply(ReorderScreens(order))
    }

    func setKind(_ kind: ScreenKind, of id: ScreenID) {
        guard let screen = project.screen(withID: id), screen.kind != kind else { return }
        apply(ScreenCommands.setKind(kind, of: id))
    }

    // MARK: Viewports (spec 8.2)

    /// Changes a screen's viewport. Regions don't move.
    func setViewport(_ viewport: Viewport, of id: ScreenID) {
        guard let screen = project.screen(withID: id), screen.viewport != viewport else { return }
        apply(ScreenCommands.setViewport(viewport, of: id))
    }

    /// A custom size typed into the sidebar's width and height fields. The same size as now changes nothing, so a
    /// preset stays a preset.
    func setSize(width: Int, height: Int, of id: ScreenID) {
        guard let screen = project.screen(withID: id),
            width != screen.viewport.width || height != screen.viewport.height
        else { return }
        guard width >= 1, height >= 1 else {
            NSSound.beep()
            return
        }
        setViewport(Viewport(width: width, height: height), of: id)
    }

    /// The viewport of the display the window is on, measured now.
    var thisDeviceViewport: Viewport? {
        displaySize().map { ViewportPresets.thisDevice(width: $0.width, height: $0.height) }
    }

    func useThisDevice(for id: ScreenID) {
        guard let viewport = thisDeviceViewport else {
            NSSound.beep()
            return
        }
        setViewport(viewport, of: id)
    }

    /// Measures the display again for a This Device viewport.
    func refreshThisDevice(for id: ScreenID) {
        guard project.screen(withID: id)?.viewport.preset == ViewportPresets.thisDeviceID else { return }
        useThisDevice(for: id)
    }

    /// Asks for a width and height, then gives the screen that custom size.
    func chooseCustomSize(for id: ScreenID) {
        guard let screen = project.screen(withID: id) else { return }
        askSize(screen.viewport) { [weak self] size in
            guard let size else { return }
            self?.setSize(width: size.width, height: size.height, of: id)
        }
    }

    /// The presets the viewport menus offer: the built-in ones, then the user's.
    var presets: (builtIn: [ViewportPreset], user: [ViewportPreset]) {
        (ViewportPresets.builtIn, presetStore.presets)
    }

    /// Asks for a name and saves the screen's viewport size as a user preset in `settings.json`, then gives the
    /// screen that preset. A settings file that can't be read is shown as an error and left as it is.
    func saveViewportAsPreset(for id: ScreenID) {
        guard let screen = project.screen(withID: id) else { return }
        askName("Save Viewport as Preset", "") { [weak self] name in
            guard let self, let name = name.flatMap(ScreenNames.cleaned) else { return }
            do {
                let preset = try self.presetStore.save(
                    name: name, width: screen.viewport.width, height: screen.viewport.height)
                self.setViewport(preset.viewport, of: id)
            } catch {
                self.showError(error)
            }
        }
    }

    // MARK: Variants (spec 8.3)

    /// Copies a screen into its variant group at `viewport`, named after the viewport, and shows the copy.
    func newVariant(of id: ScreenID, viewport: Viewport) {
        guard let screen = project.screen(withID: id) else { return }
        let label = ViewportPresets.shortName(for: viewport, userPresets: presetStore.presets)
        let variant = NewVariant(of: id, viewport: viewport, name: "\(screen.name) (\(label))")
        if apply(variant) {
            model.show(variant.newID)
        }
    }

    /// Makes `id` a variant of `target`, joining its group.
    func makeVariant(_ id: ScreenID, of target: ScreenID) {
        apply(JoinVariants(id, joining: target))
    }

    func isInVariantGroup(_ id: ScreenID) -> Bool {
        project.variantGroups.contains { $0.screens.contains(id) }
    }

    func removeFromVariantGroup(_ id: ScreenID) {
        apply(LeaveVariantGroup(id))
    }

    func renameVariantGroup(containing id: ScreenID, to name: String) {
        guard let name = ScreenNames.cleaned(name) else { return }
        apply(RenameVariantGroup(containing: id, to: name))
    }

    func promptRenameVariantGroup(containing id: ScreenID) {
        guard let group = project.variantGroups.first(where: { $0.screens.contains(id) }) else { return }
        askName("Rename Variant Group", group.name) { [weak self] name in
            guard let name else { return }
            self?.renameVariantGroup(containing: id, to: name)
        }
    }

    func ungroupVariants(containing id: ScreenID) {
        apply(UngroupVariants(containing: id))
    }

    // MARK: Following links (spec 8.4)

    /// Follows the links of `region` on the active screen: straight to the target when it has one, through a menu
    /// at `anchor` in the canvas when it has several.
    func followLinks(of region: RegionID, at anchor: CGPoint) {
        guard let screen = model.activeScreen, let found = RegionIndex(screen: screen).region(region) else { return }
        let targets = LinkTargets.entries(for: found, in: project)
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }
        guard targets.count > 1 else {
            follow(to: targets[0].screen)
            return
        }
        chooseLink(targets, anchor) { [weak self] target in
            guard let target else { return }
            self?.follow(to: target.screen)
        }
    }

    /// Shows `target` and records the screen it was followed from for Back.
    func follow(to target: ScreenID) {
        guard project.screen(withID: target) != nil else { return }
        model.history.visit(target, from: model.activeScreenID)
        model.show(target)
    }

    var canGoBack: Bool {
        model.history.canGoBack(from: model.activeScreenID, in: project)
    }

    var canGoForward: Bool {
        model.history.canGoForward(from: model.activeScreenID, in: project)
    }

    func goBack() {
        guard let target = model.history.back(from: model.activeScreenID, in: project) else { return }
        model.show(target)
    }

    func goForward() {
        guard let target = model.history.forward(from: model.activeScreenID, in: project) else { return }
        model.show(target)
    }

    /// The screen `offset` places away in the sidebar, if there is one.
    func neighbor(offset: Int) -> ScreenID? {
        ScreenNavigation.neighbor(of: model.activeScreenID, offset: offset, in: project)
    }

    func showNextScreen() {
        guard let next = neighbor(offset: 1) else { return }
        model.show(next)
    }

    func showPreviousScreen() {
        guard let previous = neighbor(offset: -1) else { return }
        model.show(previous)
    }

    // MARK: Asking the user

    private func runConfirm(_ message: String, button: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Undo brings it back."
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        run(alert) { completion($0 == .alertFirstButtonReturn) }
    }

    private func runAskName(_ title: String, initial: String, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        run(alert) { completion($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    private func runAskSize(_ current: Viewport, completion: @escaping ((width: Int, height: Int)?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Custom Size"
        alert.informativeText = "Width and height in points."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let width = NSTextField(string: String(current.width))
        let height = NSTextField(string: String(current.height))
        let times = NSTextField(labelWithString: "×")
        let stack = NSStackView(views: [width, times, height])
        stack.orientation = .horizontal
        stack.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        width.widthAnchor.constraint(equalToConstant: 80).isActive = true
        height.widthAnchor.constraint(equalToConstant: 80).isActive = true
        alert.accessoryView = stack
        alert.window.initialFirstResponder = width
        run(alert) { response in
            guard response == .alertFirstButtonReturn,
                let w = Int(width.stringValue.trimmingCharacters(in: .whitespaces)),
                let h = Int(height.stringValue.trimmingCharacters(in: .whitespaces))
            else {
                completion(nil)
                return
            }
            completion((width: w, height: h))
        }
    }

    private func runChooseLink(_ targets: [LinkTarget], at anchor: CGPoint, completion: @escaping (LinkTarget?) -> Void)
    {
        let menu = NSMenu(title: "Follow Link")
        let chooser = MenuChooser()
        for (index, target) in targets.enumerated() {
            let item = NSMenuItem(title: target.title, action: #selector(MenuChooser.choose(_:)), keyEquivalent: "")
            item.target = chooser
            item.tag = index
            menu.addItem(item)
        }
        if let view = anchorView, view.window?.isVisible == true {
            _ = menu.popUp(positioning: nil, at: anchor, in: view)
        }
        completion(chooser.chosen.map { targets[$0] })
    }

    private func runShowError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "The preset wasn’t saved."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        run(alert) { _ in }
    }

    private func run(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}

/// Remembers which item of a pop-up menu was chosen. `NSMenu.popUp` returns once the menu closes, after the item's
/// action has run.
private final class MenuChooser: NSObject {
    var chosen: Int?

    @objc func choose(_ sender: NSMenuItem) {
        chosen = sender.tag
    }
}
