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
    let toastView = ToastView(frame: .zero)
    private var shownScreenID: ScreenID?
    private var shownProject: ObjectIdentifier?
    private var shownRevision: Int?
    /// Whether the camera is the fitted default rather than one the user chose. A fitted camera is refitted when the
    /// canvas changes size, and isn't saved.
    private(set) var isFitted = false
    /// The press, drag and release in progress.
    private var gesture: CanvasGesture?
    private var gridPopover: NSPopover?
    /// The camera, and whether it was fitted, from before the details panel opened, to go back to when it closes.
    private var cameraBeforeDetails: (camera: Camera, isFitted: Bool)?
    private var cameraAnimation: Timer?

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
        toastView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toastView)
        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
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
    }

    func gridSize(for screen: Screen) -> Int {
        model.project.editorState.screens[screen.id]?.gridSize ?? Snapping.defaultGridSize
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
        guard let screen = canvasView.screen, let frame = RegionIndex(screen: screen).region(region)?.frame else {
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
        let began = CACurrentMediaTime()
        let duration = Self.cameraAnimationDuration
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let t = min((CACurrentMediaTime() - began) / duration, 1)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.canvasView.camera = Camera.interpolated(
                    from: start, to: target, fraction: eased, viewSize: self.canvasView.bounds.size)
                if t >= 1 {
                    timer.invalidate()
                    self.cameraAnimation = nil
                    completion?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cameraAnimation = timer
    }

    private func stopCameraAnimation() {
        cameraAnimation?.invalidate()
        cameraAnimation = nil
    }

    // MARK: Tools, snapping and the grid

    func choose(_ tool: Tool) {
        model.tool = tool
        canvasView.tool = tool
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
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: GridSizePicker(size: gridSize(for: screen)) { [weak self] size in
                self?.setGridSize(size)
            })
        gridPopover = popover
        updateGrid()
        if canvasView.window?.isVisible == true {
            let anchor = CGRect(x: canvasView.bounds.midX, y: 12, width: 1, height: 1)
            popover.show(relativeTo: anchor, of: canvasView, preferredEdge: .maxY)
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
        default: return false
        }
        return true
    }

    // MARK: Gestures

    private func apply(_ command: Command) {
        do {
            if let performCommand {
                try performCommand(command)
            } else {
                model.closeDetails()
                try model.session.perform(command)
                model.noteChange()
            }
        } catch {
            NSSound.beep()
        }
    }

    private func showGesture() {
        guard let gesture else { return }
        canvasView.preview = gesture.preview
        canvasView.selection = gesture.selection
    }
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
            zoom: canvasView.camera.zoom
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
        switch gesture.detailsRequest {
        case .open(let region):
            try? model.openDetails(for: region)
        case .close:
            model.closeDetails()
        case nil:
            break
        }
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
