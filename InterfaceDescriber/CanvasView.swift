import AppKit
import DescriberCore
import QuartzCore

/// Receives the canvas's clicks, drags and keys. Points are in screen points.
@MainActor
protocol CanvasInteraction: AnyObject {
    /// `clickCount` is 2 for the second press of a double-click.
    func canvasPressed(at point: CGPoint, modifiers: KeyCombo.Modifiers, clickCount: Int)
    func canvasDragged(to point: CGPoint, optionHeld: Bool)
    func canvasReleased(at point: CGPoint, optionHeld: Bool)
    func canvasOptionChanged(optionHeld: Bool)
    /// Returns whether the key was handled.
    func canvasKeyDown(_ combo: KeyCombo) -> Bool
}

/// The canvas. Each region is its own Core Animation layer, so panning moves one layer and zooming only resizes
/// layers; the milestone 4 spike found redrawing 500 regions with Core Graphics on every frame too slow. Turns
/// two-finger scrolls and pinches into camera changes, and passes clicks, drags and keys to its `interaction`. Shows
/// the selection, resize handles, and what a gesture in progress would do.
final class CanvasView: NSView {
    /// The screen to draw. Call `reload()` after it changes in place.
    var screen: Screen? {
        didSet {
            if screen !== oldValue { reload() }
        }
    }
    var camera = Camera() {
        didSet {
            guard camera != oldValue else { return }
            withoutAnimation {
                if camera.zoom == oldValue.zoom {
                    positionContent()
                } else {
                    layoutContent()
                }
                layoutGrid()
            }
        }
    }
    /// The grid size to draw, or nil to hide the grid.
    var gridSize: Int? {
        didSet {
            if gridSize != oldValue { withoutAnimation(layoutGrid) }
        }
    }
    /// Called after a gesture or a zoom command changes the camera, so it can be saved.
    var onCameraChange: ((Camera) -> Void)?
    /// Called after the view changes size.
    var onResize: (() -> Void)?
    weak var interaction: CanvasInteraction?
    /// The active tool, which decides the cursor and whether handles show.
    var tool: Tool = .select {
        didSet {
            guard tool != oldValue else { return }
            withoutAnimation(layoutHandles)
            updateCursorAtMouse()
        }
    }
    /// The selected regions, drawn with an accent border.
    var selection: [RegionID] = [] {
        didSet {
            guard selection != oldValue else { return }
            withoutAnimation(applySelection)
        }
    }
    /// The regions whose descriptions show on the canvas, from the editor state (spec Section 4).
    var visibleDescriptions: Set<RegionID> = [] {
        didSet {
            guard visibleDescriptions != oldValue else { return }
            withoutAnimation {
                for (id, layers) in regionLayers {
                    let shows = visibleDescriptions.contains(id)
                    if layers.showsDescription != shows {
                        layers.showsDescription = shows
                        layers.layout(zoom: camera.zoom)
                    }
                }
            }
        }
    }
    /// What the gesture in progress would do.
    var preview: CanvasGesture.Preview = .none {
        didSet {
            guard preview != oldValue else { return }
            withoutAnimation(applyPreview)
        }
    }

    /// Holds every canvas layer, in view coordinates with the origin at the top-left.
    let stage = CALayer()
    /// The canvas bounds, with the dashed viewport outline for a scrolling screen.
    private let boundsLayer = CALayer()
    private let viewportOutline = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    /// The regions' boxes in z-order, in zoomed screen coordinates; its position is the screen origin in the view.
    let regionsLayer = CALayer()
    /// Above the regions, in the same coordinates: the region being drawn, the marquee, and the resize handles.
    private let overlayLayer = CALayer()
    private let newRegionLayer = CALayer()
    private let marqueeLayer = CALayer()
    private let handleLayers = ResizeHandle.allCases.map { _ in CALayer() }
    private let emptyLabel = CATextLayer()
    private var regionLayers: [RegionID: RegionLayers] = [:]
    /// The screen's regions by ID, as of the last reload.
    private var regions: [RegionID: Region] = [:]
    /// The regions drawn at a previewed frame.
    private var previewedRegions: Set<RegionID> = []
    /// Whether a press started a gesture that hasn't been released yet.
    private var isTrackingGesture = false
    private let titleWidths = TitleWidths()
    private var colors = CanvasColors(appearance: NSAppearance.currentDrawing())

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }

    private func setUpLayers() {
        for layer in [stage, boundsLayer, viewportOutline, gridLayer, regionsLayer, overlayLayer] {
            layer.anchorPoint = .zero
        }
        for layer in [newRegionLayer, marqueeLayer] + handleLayers {
            layer.anchorPoint = .zero
            layer.borderWidth = 1
            layer.isHidden = true
            overlayLayer.addSublayer(layer)
        }
        viewportOutline.fillColor = nil
        viewportOutline.lineWidth = 1
        viewportOutline.lineDashPattern = [4, 3]
        boundsLayer.borderWidth = 1
        boundsLayer.addSublayer(viewportOutline)
        gridLayer.fillColor = nil
        emptyLabel.string = "No screen"
        emptyLabel.fontSize = 13
        emptyLabel.alignmentMode = .center
        stage.addSublayer(boundsLayer)
        stage.addSublayer(gridLayer)
        stage.addSublayer(regionsLayer)
        stage.addSublayer(overlayLayer)
        stage.addSublayer(emptyLabel)
        layer?.addSublayer(stage)
        applyColors()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsLayout = true
            onResize?()
        }
    }

    override func layout() {
        super.layout()
        withoutAnimation {
            stage.frame = bounds
            // Whatever AppKit does with the backing layer, the stage's origin is at the top-left like the view's.
            stage.isGeometryFlipped = !(stage.superlayer?.contentsAreFlipped() ?? false)
            emptyLabel.frame = CGRect(x: 0, y: bounds.midY - 9, width: bounds.width, height: 18)
            layoutGrid()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colors = CanvasColors(appearance: effectiveAppearance)
        withoutAnimation(applyColors)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        withoutAnimation(applyColors)
    }

    private var scale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func applyColors() {
        boundsLayer.backgroundColor = colors.boundsFill
        boundsLayer.borderColor = colors.boundsBorder
        viewportOutline.strokeColor = colors.boundsBorder
        gridLayer.strokeColor = colors.grid
        gridLayer.lineWidth = 1 / scale
        emptyLabel.foregroundColor = colors.emptyText
        emptyLabel.contentsScale = scale
        for layers in regionLayers.values {
            layers.apply(colors, scale: scale)
        }
        newRegionLayer.backgroundColor = colors.newRegionFill
        newRegionLayer.borderColor = colors.selection
        marqueeLayer.backgroundColor = colors.marqueeFill
        marqueeLayer.borderColor = colors.selection
        for handle in handleLayers {
            handle.backgroundColor = colors.handleFill
            handle.borderColor = colors.selection
        }
    }

    // MARK: Content

    /// Builds the region layers again from the screen, reusing the layers of regions that are still there.
    func reload() {
        withoutAnimation {
            emptyLabel.isHidden = screen != nil
            boundsLayer.isHidden = screen == nil
            previewedRegions = []
            guard let screen else {
                regionLayers = [:]
                regions = [:]
                regionsLayer.sublayers = nil
                layoutGrid()
                layoutOverlay()
                return
            }
            let bounds = screen.canvasBounds
            let selected = Set(selection)
            var kept: [RegionID: RegionLayers] = [:]
            var regions: [RegionID: Region] = [:]
            var boxes: [CALayer] = []
            for region in screen.allRegions {
                let layers = regionLayers[region.id] ?? RegionLayers()
                layers.update(from: region, bounds: bounds, titleWidths: titleWidths)
                layers.apply(colors, scale: scale)
                layers.isSelected = selected.contains(region.id)
                layers.showsDescription = visibleDescriptions.contains(region.id)
                kept[region.id] = layers
                regions[region.id] = region
                boxes.append(layers.box)
            }
            regionLayers = kept
            self.regions = regions
            regionsLayer.sublayers = boxes
            if case .frames(let frames) = preview {
                showPreviewFrames(frames)
            }
            layoutContent()
            layoutGrid()
        }
    }

    /// The number of regions with a layer.
    var regionLayerCount: Int {
        regionLayers.count
    }

    /// Sizes everything for the camera's zoom, then positions it.
    private func layoutContent() {
        guard let screen else { return }
        let zoom = camera.zoom
        boundsLayer.bounds = CGRect(origin: .zero, size: RegionLayers.zoomed(screen.canvasBounds, zoom).size)
        if screen.scroll != nil {
            viewportOutline.isHidden = false
            viewportOutline.path = CGPath(rect: RegionLayers.zoomed(screen.viewportFrame, zoom), transform: nil)
        } else {
            viewportOutline.isHidden = true
        }
        for layers in regionLayers.values {
            layers.layout(zoom: zoom)
        }
        layoutOverlay()
        positionContent()
    }

    /// Moves the content for the camera's pan. Nothing is resized or redrawn.
    private func positionContent() {
        let origin = camera.viewPoint(fromScreen: .zero)
        regionsLayer.position = origin
        overlayLayer.position = origin
        if let screen {
            boundsLayer.position = camera.viewPoint(fromScreen: screen.canvasBounds.cgRect.origin)
        }
    }

    // MARK: Selection and previews

    /// The regions whose layers show as selected, for tests.
    var selectedLayerIDs: Set<RegionID> {
        Set(regionLayers.filter { $0.value.isSelected }.keys)
    }

    /// The regions whose layers are drawing a description, for tests.
    var describedLayerIDs: Set<RegionID> {
        Set(regionLayers.filter { $0.value.isShowingDescription }.keys)
    }

    /// The regions whose layers are drawing the link indicator, for tests.
    var linkedLayerIDs: Set<RegionID> {
        Set(regionLayers.filter { $0.value.isShowingLinkIndicator }.keys)
    }

    /// Whether the resize handles are showing, for tests.
    var showsHandles: Bool {
        !handleLayers[0].isHidden
    }

    private func applySelection() {
        let selected = Set(selection)
        for (id, layers) in regionLayers {
            layers.isSelected = selected.contains(id)
        }
        layoutHandles()
    }

    private func applyPreview() {
        if case .frames(let frames) = preview {
            showPreviewFrames(frames)
        } else {
            showPreviewFrames([:])
        }
        layoutOverlay()
    }

    /// Draws the regions in `frames` at those frames, and every other region that had a previewed frame at its own.
    private func showPreviewFrames(_ frames: [RegionID: Frame]) {
        guard let screen else { return }
        let bounds = screen.canvasBounds
        for id in previewedRegions where frames[id] == nil {
            guard let region = regions[id], let layers = regionLayers[id] else { continue }
            layers.setFrame(region.frame, bounds: bounds)
            layers.layout(zoom: camera.zoom)
        }
        for (id, frame) in frames {
            guard let layers = regionLayers[id] else { continue }
            layers.setFrame(frame, bounds: bounds)
            layers.layout(zoom: camera.zoom)
        }
        previewedRegions = Set(frames.keys)
    }

    /// Lays out the region being drawn, the marquee and the handles for the camera's zoom.
    private func layoutOverlay() {
        let zoom = camera.zoom
        switch preview {
        case .newRegion(let frame):
            newRegionLayer.isHidden = false
            newRegionLayer.frame = RegionLayers.zoomed(frame, zoom)
            marqueeLayer.isHidden = true
        case .marquee(let rect):
            marqueeLayer.isHidden = false
            marqueeLayer.frame = CGRect(
                x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
            newRegionLayer.isHidden = true
        case .none, .frames:
            newRegionLayer.isHidden = true
            marqueeLayer.isHidden = true
        }
        layoutHandles()
    }

    /// The frame the handles go around: the single selected region's, while the Select tool is active.
    private var handleFrame: Frame? {
        guard tool == .select, selection.count == 1, let id = selection.first, let region = regions[id] else {
            return nil
        }
        if case .frames(let frames) = preview, let frame = frames[id] {
            return frame
        }
        return region.frame
    }

    /// The handles' side, in view points, at every zoom.
    static let handleSize: CGFloat = 7

    private func layoutHandles() {
        guard let frame = handleFrame else {
            for handle in handleLayers {
                handle.isHidden = true
            }
            return
        }
        let rect = RegionLayers.zoomed(frame, camera.zoom)
        let size = Self.handleSize
        for (handle, layer) in zip(ResizeHandle.allCases, handleLayers) {
            let center = handle.point(on: rect)
            layer.isHidden = false
            layer.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        }
    }

    private func layoutGrid() {
        guard screen != nil, let gridSize else {
            gridLayer.path = nil
            return
        }
        let step = GridLines.drawnStep(grid: gridSize, zoom: camera.zoom)
        let visible = camera.visibleRect(viewSize: bounds.size)
        let path = CGMutablePath()
        for x in GridLines.positions(from: visible.minX, to: visible.maxX, grid: step) {
            let viewX = camera.viewPoint(fromScreen: CGPoint(x: x, y: 0)).x
            path.move(to: CGPoint(x: viewX, y: 0))
            path.addLine(to: CGPoint(x: viewX, y: bounds.height))
        }
        for y in GridLines.positions(from: visible.minY, to: visible.maxY, grid: step) {
            let viewY = camera.viewPoint(fromScreen: CGPoint(x: 0, y: y)).y
            path.move(to: CGPoint(x: 0, y: viewY))
            path.addLine(to: CGPoint(x: bounds.width, y: viewY))
        }
        gridLayer.frame = CGRect(origin: .zero, size: bounds.size)
        gridLayer.path = path
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    // MARK: Gestures

    override func scrollWheel(with event: NSEvent) {
        guard screen != nil else {
            super.scrollWheel(with: event)
            return
        }
        // A mouse wheel reports lines rather than points.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        change(to: camera.panned(byViewDX: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale))
    }

    override func magnify(with event: NSEvent) {
        guard screen != nil else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        change(to: camera.zoomed(to: camera.zoom * (1 + event.magnification), anchor: anchor))
    }

    // MARK: Clicks, drags and keys

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func screenPoint(of event: NSEvent) -> CGPoint {
        camera.screenPoint(fromView: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard screen != nil, let interaction else { return }
        isTrackingGesture = true
        interaction.canvasPressed(
            at: screenPoint(of: event), modifiers: KeyCombo.Modifiers(event.modifierFlags), clickCount: event.clickCount
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingGesture else { return }
        interaction?.canvasDragged(to: screenPoint(of: event), optionHeld: event.modifierFlags.contains(.option))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingGesture else { return }
        isTrackingGesture = false
        interaction?.canvasReleased(at: screenPoint(of: event), optionHeld: event.modifierFlags.contains(.option))
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func flagsChanged(with event: NSEvent) {
        if isTrackingGesture {
            interaction?.canvasOptionChanged(optionHeld: event.modifierFlags.contains(.option))
        }
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let combo = KeyCombo(event: event), interaction?.canvasKeyDown(combo) == true {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                    owner: self))
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursorAtMouse() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(point) {
            updateCursor(at: point)
        }
    }

    /// Crosshair for the Region tool; resize cursors over the handles; the arrow otherwise.
    private func updateCursor(at viewPoint: CGPoint) {
        cursor(at: viewPoint).set()
    }

    func cursor(at viewPoint: CGPoint) -> NSCursor {
        if tool == .region, screen != nil {
            return .crosshair
        }
        if let frame = handleFrame,
            let handle = ResizeHandle.handle(
                at: camera.screenPoint(fromView: viewPoint), on: frame.cgRect,
                radius: CanvasGesture.handleRadius / camera.zoom)
        {
            switch handle {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            default: return .crosshair
            }
        }
        return .arrow
    }

    /// Sets the camera as the user's choice, so it is saved.
    func change(to newCamera: Camera) {
        camera = newCamera
        onCameraChange?(newCamera)
    }
}
