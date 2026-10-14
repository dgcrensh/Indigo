import AppKit
import DescriberCore
import Observation
import QuartzCore
import SwiftUI

/// Shows the document's active screen in a `CanvasView`. Keeps each screen's zoom, pan and grid size in the
/// project's editor state, draws again after every change to the project, and turns clicks and drags into commands
/// through `CanvasGesture`.
final class CanvasViewController: NSViewController {
    /// Space around the viewport when a screen is fitted into the canvas, and around a region open in the details
    /// panel.
    static let fitPadding = 40.0
    /// How far zoom-to-fit zooms in on a region open in the details panel, so a small one doesn't fill the canvas.
    static let detailsMaximumZoom = 4.0
    /// How long the canvas takes to zoom to a region and back. Nothing animates while the window is off screen.
    static let cameraAnimationDuration = 0.25

    let model: DocumentModel
    /// Performs a command as one undo step. The document sets this to `Document.perform(_:)`; without it, commands
    /// go straight to the edit session.
    var performCommand: ((Command) throws -> Void)?
    let canvasView = CanvasView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    let toastView = ToastView()
    /// The floating tools at the bottom center of the canvas.
    let toolPill = ToolPill()
    /// How far the tool pill sits from the canvas's bottom edge, and the toast from the pill.
    static let toolPillInset: CGFloat = 20
    static let toastGap: CGFloat = 12
    /// Shown while `settings.json` can't be used. The window controller sets its message.
    let settingsBanner = SettingsBanner()
    private var shownScreenID: ScreenID?
    private var shownProject: ObjectIdentifier?
    private var shownRevision: Int?
    /// Whether the camera is the fitted default rather than one the user chose. A fitted camera is refitted when the
    /// canvas changes size, and isn't saved.
    private(set) var isFitted = false
    /// The press, drag and release in progress.
    private var gesture: CanvasGesture?
    /// The part of a scroll smaller than a point, kept for the next scroll event of the same region.
    private var scrollRemainder: (region: RegionID, x: Double, y: Double)?
    private var gridPopover: NSPopover?
    /// The camera, and whether it was fitted, from before the details panel opened, to go back to when it closes.
    private var cameraBeforeDetails: (camera: Camera, isFitted: Bool)?
    /// The camera animation in progress, stepped by the canvas's display link so each step lands on a frame.
    private var cameraAnimation: CameraAnimation?
    /// Follows the links of a region, given a point in the canvas view to show a menu at when it has several. The
    /// window controller sets this to its screen controller.
    var followLinks: ((RegionID, CGPoint) -> Void)?
    /// Where Copy writes regions and Paste reads them. Tests use a private pasteboard.
    var pasteboard = NSPasteboard.general
    /// Asks whether to delete regions that have regions inside them, and calls back with the answer. Shows a sheet
    /// on the window; tests replace it.
    lazy var confirmDelete: (_ message: String, _ completion: @escaping (Bool) -> Void) -> Void = {
        [weak self] message, completion in
        self?.showDeleteAlert(message, completion: completion)
    }

    init(model: DocumentModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        let container = NSView(frame: canvasView.frame)
        canvasView.autoresizingMask = [.width, .height]
        canvasView.interaction = self
        canvasView.onCameraChange = { [weak self] camera in
            self?.save(camera)
        }
        canvasView.onResize = { [weak self] in
            guard let self, self.isFitted, let screen = self.canvasView.screen else { return }
            self.fit(screen)
        }
        container.addSubview(canvasView)
        toolPill.translatesAutoresizingMaskIntoConstraints = false
        toolPill.onChooseTool = { [weak self] tool in
            self?.choose(tool)
        }
        toolPill.onSnap = { [weak self] optionHeld in
            if optionHeld {
                self?.toggleGridSizePopover()
            } else {
                self?.toggleSnapping()
            }
        }
        container.addSubview(toolPill)
        toastView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toastView)
        settingsBanner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsBanner)
        // As wide as there is room for, up to 640 pt.
        let bannerWidth = settingsBanner.widthAnchor.constraint(equalToConstant: 640)
        bannerWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toolPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toolPill.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.toolPillInset),
            toastView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: toolPill.topAnchor, constant: -Self.toastGap),
            settingsBanner.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsBanner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            settingsBanner.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
            bannerWidth,
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        update()
        observeModel()
    }

    /// Calls `update()` after the next change to what the canvas shows, then watches again.
    private func observeModel() {
        withObservationTracking {
            _ = model.revision
            _ = model.activeScreenID
            _ = model.snappingEnabled
            _ = model.tool
            _ = model.selection
            _ = model.settings
        } onChange: { [weak self] in
            let controller = self
            Task { @MainActor in
                controller?.update()
                controller?.observeModel()
            }
        }
    }

    /// Shows the active screen as the model has it now, restoring its camera when the screen or project changed.
    /// Rebuilds the region layers only when the project changed.
    func update() {
        let screen = model.activeScreen
        canvasView.scrollOffsets = screen.map(scrollOffsets(for:)) ?? [:]
        canvasView.screen = screen
        let project = ObjectIdentifier(model.project)
        let screenChanged = screen?.id != shownScreenID || project != shownProject
        if screenChanged {
            shownScreenID = screen?.id
            shownProject = project
            // The details panel shows a region on the screen that was showing; commit it and keep this screen's camera.
            stopCameraAnimation()
            cameraBeforeDetails = nil
            if let details = model.details, details.screen != screen?.id {
                model.closeDetails()
            }
            restoreCamera(for: screen)
            setSelection([])
        } else if let screen {
            setSelection(DescriberCore.Selection.pruned(model.selection, to: screen))
        }
        if screenChanged || model.revision != shownRevision {
            shownRevision = model.revision
            canvasView.reload()
        }
        canvasView.tool = model.tool
        canvasView.visibleDescriptions = model.project.editorState.visibleDescriptions
        if gesture == nil {
            canvasView.selection = model.selection
        }
        updateGrid()
    }

    /// Sets the model's selection, leaving it alone when it wouldn't change so observers aren't woken for nothing.
    private func setSelection(_ selection: [RegionID]) {
        if model.selection != selection {
            model.selection = selection
        }
    }

    private func updateGrid() {
        let showsGrid = model.snappingEnabled || gridPopover != nil
        canvasView.gridSize = canvasView.screen.flatMap { showsGrid ? gridSize(for: $0) : nil }
        updateToolPill()
    }

    /// Shows the tool, snapping and grid size in the pill, whatever changed them.
    private func updateToolPill() {
        toolPill.update(
            tool: model.tool, snapping: model.snappingEnabled,
            gridSize: canvasView.screen.map(gridSize(for:)) ?? model.settings.gridSize, keybinds: model.keybinds)
    }

    func gridSize(for screen: Screen) -> Int {
        model.project.editorState.screens[screen.id]?.gridSize ?? model.settings.gridSize
    }

    /// How far each scrolling region on `screen` is scrolled, from its editor state.
    func scrollOffsets(for screen: Screen) -> [RegionID: ScrollOffset] {
        model.project.editorState.screens[screen.id]?.scrollOffsets ?? [:]
    }

    /// Where `screen`'s regions are drawn at their scroll positions.
    private func scrollLayout(for screen: Screen) -> ScrollLayout {
        ScrollLayout(screen: screen, offsets: scrollOffsets(for: screen))
    }

    /// The saved camera, or the viewport fitted into the canvas when there is none.
    private func restoreCamera(for screen: Screen?) {
        guard let screen else {
            isFitted = false
            return
        }
        if let state = model.project.editorState.screens[screen.id] {
            isFitted = false
            canvasView.camera = Camera(state)
        } else {
            isFitted = true
            fit(screen)
        }
    }

    private func fit(_ screen: Screen) {
        canvasView.camera = Camera.fitting(
            screen.viewportFrame.cgRect,
            viewSize: canvasView.bounds.size,
            padding: Self.fitPadding,
            maximumZoom: 1
        )
    }

    /// The editor state of the shown screen, starting from the current camera when it has none, so writing it
    /// doesn't lose the zoom and pan the canvas shows.
    private var shownScreenState: ScreenEditorState? {
        guard let id = shownScreenID else { return nil }
        return model.project.editorState.screens[id] ?? canvasView.camera.applied(to: ScreenEditorState())
    }

    /// Keeps a camera the user chose in the editor state. Zoom and pan are view state, not edits, so this is not
    /// undoable and doesn't mark the document as changed; the next save writes it.
    private func save(_ camera: Camera) {
        guard let id = shownScreenID, let state = shownScreenState else { return }
        isFitted = false
        model.project.editorState.screens[id] = camera.applied(to: state)
    }

    // MARK: Zoom commands

    private var center: CGPoint {
        CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
    }

    func zoomIn() {
        guard canvasView.screen != nil else { return }
        canvasView.change(to: canvasView.camera.zoomedIn(anchor: center))
    }

    func zoomOut() {
        guard canvasView.screen != nil else { return }
        canvasView.change(to: canvasView.camera.zoomedOut(anchor: center))
    }

    /// 100 % with the viewport centered.
    func actualSize() {
        guard let screen = canvasView.screen else { return }
        canvasView.change(to: .actualSize(centering: screen.viewportFrame.cgRect, viewSize: canvasView.bounds.size))
    }

    // MARK: Details panel camera

    /// Remembers the camera to go back to when the details panel closes, and stops refitting the screen while the
    /// panel changes the canvas's size. Does nothing while the panel is already open.
    func prepareForDetails() {
        guard cameraBeforeDetails == nil else { return }
        cameraBeforeDetails = (canvasView.camera, isFitted)
        isFitted = false
    }

    /// Animates the canvas to fit `region` in a canvas `canvasWidth` wide, remembering the camera from before the
    /// panel opened. The fitted camera isn't saved as the user's.
    func fitForDetails(_ region: RegionID, canvasWidth: CGFloat) {
        guard let screen = canvasView.screen, let frame = scrollLayout(for: screen).drawnFrame(of: region) else {
            return
        }
        prepareForDetails()
        let size = CGSize(width: max(canvasWidth, 1), height: canvasView.bounds.height)
        let target = Camera.fitting(
            frame.cgRect, viewSize: size, padding: Self.fitPadding, maximumZoom: Self.detailsMaximumZoom)
        animateCamera(to: target, completion: nil)
    }

    /// Animates the canvas back to the camera it had before the details panel opened.
    func restoreAfterDetails() {
        guard let before = cameraBeforeDetails else { return }
        cameraBeforeDetails = nil
        animateCamera(to: before.camera) { [weak self] in
            guard let self else { return }
            self.isFitted = before.isFitted
            if before.isFitted, let screen = self.canvasView.screen {
                self.fit(screen)
            } else {
                self.save(before.camera)
            }
        }
    }

    var isShowingDetailsCamera: Bool {
        cameraBeforeDetails != nil
    }

    private func animateCamera(to target: Camera, completion: (() -> Void)?) {
        stopCameraAnimation()
        let start = canvasView.camera
        guard canvasView.window?.isVisible == true, start != target else {
            canvasView.camera = target
            completion?()
            return
        }
        let link = canvasView.displayLink(target: self, selector: #selector(stepCameraAnimation(_:)))
        cameraAnimation = CameraAnimation(
            start: start, target: target, began: CACurrentMediaTime(), completion: completion, link: link)
        link.add(to: .main, forMode: .common)
    }

    /// Moves the camera to where the animation is at the time of the frame being drawn.
    @objc private func stepCameraAnimation(_ link: CADisplayLink) {
        guard let animation = cameraAnimation, animation.link === link else {
            link.invalidate()
            return
        }
        let t = min(max((link.targetTimestamp - animation.began) / Self.cameraAnimationDuration, 0), 1)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        canvasView.camera = Camera.interpolated(
            from: animation.start, to: animation.target, fraction: eased, viewSize: canvasView.bounds.size)
        if t >= 1 {
            link.invalidate()
            cameraAnimation = nil
            animation.completion?()
        }
    }

    private func stopCameraAnimation() {
        cameraAnimation?.link.invalidate()
        cameraAnimation = nil
    }

    // MARK: Tools, snapping and the grid

    func choose(_ tool: Tool) {
        model.tool = tool
        canvasView.tool = tool
        updateToolPill()
        show(.tool(tool))
    }

    func toggleSnapping() {
        model.snappingEnabled.toggle()
        show(.snapping(on: model.snappingEnabled))
        updateGrid()
    }

    private func show(_ toast: Toast) {
        toastView.show(toast.text(keybinds: model.keybinds))
    }

    /// Sets the shown screen's grid size. Editor state like zoom: it never moves a region and isn't undoable.
    func setGridSize(_ size: Int) {
        guard let id = shownScreenID, var state = shownScreenState else { return }
        state.gridSize = size
        model.project.editorState.screens[id] = state
        isFitted = false
        show(.gridSize(size))
        updateGrid()
    }

    /// Opens the grid-size slider, or closes it if it is open. The grid shows while it is open.
    func toggleGridSizePopover() {
        if let gridPopover {
            if gridPopover.isShown {
                gridPopover.performClose(nil)
            } else {
                self.gridPopover = nil
                updateGrid()
            }
            return
        }
        guard let screen = canvasView.screen else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.hasFullSizeContent = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: GridSizePicker(size: gridSize(for: screen)) { [weak self] size in
                self?.setGridSize(size)
            })
        gridPopover = popover
        updateGrid()
        if canvasView.window?.isVisible == true {
            // Above the snap button: its top edge is min Y when it is flipped.
            let button = toolPill.snapButton
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .minY : .maxY)
        }
    }

    var isShowingGridSizePopover: Bool {
        gridPopover != nil
    }

    /// Runs a keybind the canvas received. Menu key equivalents usually get these first.
    func handle(_ action: KeyAction) -> Bool {
        switch action {
        case .selectTool: choose(.select)
        case .regionTool: choose(.region)
        case .writeTool: choose(.write)
        case .toggleSnapping: toggleSnapping()
        case .gridSize: toggleGridSizePopover()
        case .selectAll: selectAll()
        case .selectParent: selectParent()
        case .selectChildren: selectChildren()
        case .delete: deleteSelection()
        case .copy: copySelection()
        case .paste: paste()
        case .duplicate: duplicate()
        case .bringToFront: reorderSelection(to: .front)
        case .sendToBack: reorderSelection(to: .back)
        case .toggleDescription: toggleDescriptions(all: false)
        case .toggleAllDescriptions: toggleDescriptions(all: true)
        case .followLink: followSelectedLink()
        case .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .nudgeLeftFar, .nudgeRightFar, .nudgeUpFar, .nudgeDownFar:
            nudge(action)
        default: return false
        }
        return true
    }

    // MARK: Selection and editing (spec Section 7)

    /// The selection as it stands on the shown screen, leaving out regions that are gone.
    private var currentSelection: [RegionID] {
        guard let screen = model.activeScreen else { return [] }
        return DescriberCore.Selection.pruned(model.selection, to: screen)
    }

    /// Whether there is a selection to copy, delete, nudge or reorder.
    var hasSelection: Bool {
        !currentSelection.isEmpty
    }

    func selectAll() {
        guard let screen = model.activeScreen else { return }
        setSelection(DescriberCore.Selection.all(on: screen))
    }

    /// Replaces the selection with the selected regions' parents. Nothing changes when none has one.
    func selectParent() {
        guard let screen = model.activeScreen else { return }
        let parents = DescriberCore.Selection.parents(of: currentSelection, on: screen)
        guard !parents.isEmpty else {
            NSSound.beep()
            return
        }
        setSelection(parents)
    }

    /// Replaces the selection with the selected regions' direct children. Nothing changes when they have none.
    func selectChildren() {
        guard let screen = model.activeScreen else { return }
        let children = DescriberCore.Selection.children(of: currentSelection, on: screen)
        guard !children.isEmpty else {
            NSSound.beep()
            return
        }
        setSelection(children)
    }

    /// Deletes the selection and everything inside it as one step, asking first when it has regions inside.
    func deleteSelection() {
        // A region open in the details panel is committed first; a new one with a blank title disappears then.
        model.closeDetails()
        guard let screen = model.activeScreen else { return }
        let selection = currentSelection
        guard !selection.isEmpty else { return }
        let delete = DeleteRegions(screen: screen.id, regions: selection)
        guard let message = DeleteConfirmation.message(deleting: selection, on: screen) else {
            apply(delete)
            return
        }
        confirmDelete(message) { [weak self] confirmed in
            guard confirmed, let self, self.model.activeScreenID == screen.id else { return }
            self.apply(delete)
        }
    }

    private func showDeleteAlert(_ message: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Undo brings them back."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if let window = view.window, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                completion(response == .alertFirstButtonReturn)
            }
        } else {
            completion(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    /// The pasteboard type for copied regions, as the core's clipboard JSON.
    static let regionsPasteboardType = NSPasteboard.PasteboardType(AppIdentity.documentTypeIdentifier + ".regions")

    /// Puts the selected regions on the pasteboard, with their titles as plain text.
    func copySelection() {
        guard let screen = model.activeScreen,
            let clipboard = RegionClipboard(copying: currentSelection, on: screen)
        else { return }
        pasteboard.clearContents()
        pasteboard.setData(clipboard.data(in: model.project), forType: Self.regionsPasteboardType)
        pasteboard.setString(clipboard.text, forType: .string)
    }

    /// The regions on the pasteboard, if it holds any.
    private var pastedClipboard: RegionClipboard? {
        pasteboard.data(forType: Self.regionsPasteboardType).flatMap { try? RegionClipboard(data: $0) }
    }

    var canPaste: Bool {
        model.activeScreen != nil && pasteboard.availableType(from: [Self.regionsPasteboardType]) != nil
    }

    /// Pastes the regions on the pasteboard onto the shown screen as one step, and selects the copies.
    func paste() {
        guard let clipboard = pastedClipboard else { return }
        paste(clipboard, actionName: "Paste")
    }

    /// Copies the selection beside itself as one step, and selects the copies. Leaves the pasteboard alone.
    func duplicate() {
        guard let screen = model.activeScreen,
            let clipboard = RegionClipboard(copying: currentSelection, on: screen)
        else { return }
        paste(clipboard, actionName: "Duplicate")
    }

    private func paste(_ clipboard: RegionClipboard, actionName: String) {
        model.closeDetails()
        guard let screen = model.activeScreen else { return }
        let command = clipboard.paste(
            onto: screen, in: model.project, grid: gridSize(for: screen), actionName: actionName,
            scrollOffsets: scrollOffsets(for: screen))
        if apply(command) {
            setSelection(command.pasted.map(\.id))
        }
    }

    /// Moves the selection by one grid step, or four with Shift; by 1 pt and 4 pt with snapping off.
    func nudge(_ action: KeyAction) {
        model.closeDetails()
        guard let screen = model.activeScreen,
            let delta = Nudge.delta(for: action, grid: gridSize(for: screen), snapping: model.snappingEnabled)
        else { return }
        let selection = currentSelection
        guard !selection.isEmpty else { return }
        apply(
            MoveRegions(
                screen: screen.id, regions: selection, dx: delta.dx, dy: delta.dy,
                scrollOffsets: scrollOffsets(for: screen)))
    }

    /// Brings the selection to the front or sends it to the back of its siblings.
    func reorderSelection(to position: ReorderRegion.Position) {
        model.closeDetails()
        guard let screen = model.activeScreen else { return }
        let selection = currentSelection
        guard !selection.isEmpty else { return }
        apply(ReorderRegions(screen: screen.id, regions: selection, to: position))
    }

    /// Shows or hides descriptions on the canvas: the selection's with `D`, every region's on the screen with
    /// `Shift-D`. Editor state like zoom, so it isn't undoable; the next save writes it.
    func toggleDescriptions(all: Bool) {
        guard let screen = model.activeScreen else { return }
        let regions = all ? DescriberCore.Selection.all(on: screen) : currentSelection
        guard !regions.isEmpty else { return }
        let state = model.project.editorState
        model.project.editorState.visibleDescriptions = DescriptionVisibility.toggling(
            regions, in: state.visibleDescriptions)
        canvasView.visibleDescriptions = model.project.editorState.visibleDescriptions
    }

    // MARK: Following links (spec 8.4)

    /// The one selected region, when it has links.
    private var selectedLinkedRegion: Region? {
        let selection = currentSelection
        guard selection.count == 1, let screen = model.activeScreen,
            let region = RegionIndex(screen: screen).region(selection[0]), !region.links.isEmpty
        else { return nil }
        return region
    }

    /// Whether `L` has a region to follow: one selected region with links.
    var canFollowLink: Bool {
        selectedLinkedRegion != nil
    }

    /// Follows the selected region's links, with a menu under the region when it has several.
    func followSelectedLink() {
        guard let region = selectedLinkedRegion else {
            NSSound.beep()
            return
        }
        model.closeDetails()
        let frame = model.activeScreen.flatMap { scrollLayout(for: $0).drawnFrame(of: region.id) } ?? region.frame
        let anchor = canvasView.camera.viewPoint(fromScreen: CGPoint(x: frame.x, y: frame.maxY))
        followLinks?(region.id, anchor)
    }

    // MARK: Gestures

    /// Performs `command` as one step, and returns whether it was applied. A command with nothing to do, such as
    /// bringing the frontmost region to the front, changes nothing quietly; any other failure beeps.
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

    private func showGesture() {
        guard let gesture else { return }
        canvasView.preview = gesture.preview
        canvasView.selection = gesture.selection
    }
}

/// A camera animation: where it goes from and to, when it began, what runs at the end, and the display link
/// stepping it.
private struct CameraAnimation {
    var start: Camera
    var target: Camera
    var began: CFTimeInterval
    var completion: (() -> Void)?
    var link: CADisplayLink
}

extension CanvasViewController: CanvasInteraction {
    func canvasPressed(at point: CGPoint, modifiers: KeyCombo.Modifiers, clickCount: Int = 1) {
        guard let screen = model.activeScreen else { return }
        let context = GestureContext(
            screen: screen,
            tool: model.tool,
            selection: model.selection,
            snappingEnabled: model.snappingEnabled,
            gridSize: gridSize(for: screen),
            zoom: canvasView.camera.zoom,
            scrollOffsets: scrollOffsets(for: screen)
        )
        gesture = CanvasGesture(pressAt: point, modifiers: modifiers, clickCount: clickCount, context: context)
        showGesture()
    }

    func canvasDragged(to point: CGPoint, optionHeld: Bool) {
        gesture?.drag(to: point, optionHeld: optionHeld)
        showGesture()
    }

    func canvasOptionChanged(optionHeld: Bool) {
        gesture?.update(optionHeld: optionHeld)
        showGesture()
    }

    func canvasReleased(at point: CGPoint, optionHeld: Bool) {
        guard var gesture else { return }
        let command = gesture.release(at: point, optionHeld: optionHeld)
        self.gesture = nil
        canvasView.preview = .none
        if let create = command as? CreateRegion {
            // A drawn region opens in the details panel, and is recorded when the panel closes (spec 6.1).
            do {
                try model.openDetails(creating: create)
            } catch {
                NSSound.beep()
            }
        } else if let command {
            apply(command)
        }
        setSelection(gesture.selection)
        canvasView.selection = gesture.selection
        if let region = gesture.linkRequest {
            model.closeDetails()
            followLinks?(region, canvasView.camera.viewPoint(fromScreen: point))
            return
        }
        switch gesture.detailsRequest {
        case .open(let region):
            try? model.openDetails(for: region)
        case .close:
            model.closeDetails()
        case nil:
            break
        }
    }

    func canvasScrollTarget(at point: CGPoint) -> RegionID? {
        guard let screen = model.activeScreen else { return nil }
        return scrollLayout(for: screen).scrollTarget(at: point, among: currentSelection)
    }

    /// Scrolls `region`'s content so it follows the fingers, and keeps the offset in the screen's editor state. Like
    /// zoom, scrolling isn't an edit: it isn't undoable and the next save writes it.
    func canvasScroll(_ region: RegionID, byViewDX dx: Double, dy: Double) {
        guard let screen = model.activeScreen, screen.id == shownScreenID, var state = shownScreenState else { return }
        let zoom = canvasView.camera.zoom
        var pending: (region: RegionID, x: Double, y: Double) = (region, 0, 0)
        if let remainder = scrollRemainder, remainder.region == region {
            pending = remainder
        }
        pending.x -= dx / zoom
        pending.y -= dy / zoom
        let stepX = Int(pending.x.rounded(.towardZero))
        let stepY = Int(pending.y.rounded(.towardZero))
        pending.x -= Double(stepX)
        pending.y -= Double(stepY)
        scrollRemainder = pending
        guard stepX != 0 || stepY != 0,
            let offset = ScrollLayout(screen: screen, offsets: state.scrollOffsets).scrolled(
                region, byDX: stepX, dy: stepY)
        else { return }
        state.scrollOffsets[region] = offset == .zero ? nil : offset
        model.project.editorState.screens[screen.id] = state
        isFitted = false
        canvasView.scrollOffsets = state.scrollOffsets
    }

    func canvasKeyDown(_ combo: KeyCombo) -> Bool {
        if combo == KeyCombo("escape"), model.details != nil {
            model.closeDetails()
            return true
        }
        guard let action = model.keybinds.action(for: combo) else { return false }
        return handle(action)
    }
}

extension CanvasViewController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        gridPopover = nil
        updateGrid()
    }
}
