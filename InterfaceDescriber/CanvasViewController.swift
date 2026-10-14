import AppKit
import DescriberCore
import Observation

/// Shows the document's active screen in a `CanvasView`. Keeps each screen's zoom and pan in the project's editor
/// state, and draws again after every change to the project.
final class CanvasViewController: NSViewController {
    /// Space around the viewport when a screen is fitted into the canvas.
    static let fitPadding = 40.0

    let model: DocumentModel
    private var shownScreenID: ScreenID?
    private var shownProject: ObjectIdentifier?
    /// Whether the camera is the fitted default rather than one the user chose. A fitted camera is refitted when the
    /// canvas changes size, and isn't saved.
    private(set) var isFitted = false

    init(model: DocumentModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var canvasView: CanvasView {
        view as! CanvasView
    }

    override func loadView() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        canvas.onCameraChange = { [weak self] camera in
            self?.save(camera)
        }
        canvas.onResize = { [weak self] in
            guard let self, self.isFitted, let screen = self.canvasView.screen else { return }
            self.fit(screen)
        }
        view = canvas
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
        } onChange: { [weak self] in
            let controller = self
            Task { @MainActor in
                controller?.update()
                controller?.observeModel()
            }
        }
    }

    /// Shows the active screen as the model has it now, restoring its camera when the screen or project changed.
    func update() {
        let screen = model.activeScreen
        canvasView.screen = screen
        let project = ObjectIdentifier(model.project)
        if screen?.id != shownScreenID || project != shownProject {
            shownScreenID = screen?.id
            shownProject = project
            restoreCamera(for: screen)
        }
        canvasView.gridSize = screen.flatMap { model.snappingEnabled ? gridSize(for: $0) : nil }
        canvasView.needsDisplay = true
    }

    private func gridSize(for screen: Screen) -> Int {
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

    /// Keeps a camera the user chose in the editor state. Zoom and pan are view state, not edits, so this is not
    /// undoable and doesn't mark the document as changed; the next save writes it.
    private func save(_ camera: Camera) {
        guard let id = shownScreenID else { return }
        isFitted = false
        let editorState = model.project.editorState
        model.project.editorState.screens[id] = camera.applied(to: editorState.screens[id] ?? ScreenEditorState())
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
}
