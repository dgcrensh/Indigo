import AppKit
import DescriberCore
import QuartzCore

/// The canvas. Each region is its own Core Animation layer, so panning moves one layer and zooming only resizes
/// layers; the milestone 4 spike found redrawing 500 regions with Core Graphics on every frame too slow. Turns
/// two-finger scrolls and pinches into camera changes. Tools and clicks arrive in milestone 5.
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

    /// Holds every canvas layer, in view coordinates with the origin at the top-left.
    let stage = CALayer()
    /// The canvas bounds, with the dashed viewport outline for a scrolling screen.
    private let boundsLayer = CALayer()
    private let viewportOutline = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    /// The regions' boxes in z-order, in zoomed screen coordinates; its position is the screen origin in the view.
    let regionsLayer = CALayer()
    private let emptyLabel = CATextLayer()
    private var regionLayers: [RegionID: RegionLayers] = [:]
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
        for layer in [stage, boundsLayer, viewportOutline, gridLayer, regionsLayer] {
            layer.anchorPoint = .zero
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
    }

    // MARK: Content

    /// Builds the region layers again from the screen, reusing the layers of regions that are still there.
    func reload() {
        withoutAnimation {
            emptyLabel.isHidden = screen != nil
            boundsLayer.isHidden = screen == nil
            guard let screen else {
                regionLayers = [:]
                regionsLayer.sublayers = nil
                layoutGrid()
                return
            }
            let bounds = screen.canvasBounds
            var kept: [RegionID: RegionLayers] = [:]
            var boxes: [CALayer] = []
            for region in screen.allRegions {
                let layers = regionLayers[region.id] ?? RegionLayers()
                layers.update(from: region, bounds: bounds, titleWidths: titleWidths)
                layers.apply(colors, scale: scale)
                kept[region.id] = layers
                boxes.append(layers.box)
            }
            regionLayers = kept
            regionsLayer.sublayers = boxes
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
        positionContent()
    }

    /// Moves the content for the camera's pan. Nothing is resized or redrawn.
    private func positionContent() {
        let origin = camera.viewPoint(fromScreen: .zero)
        regionsLayer.position = origin
        if let screen {
            boundsLayer.position = camera.viewPoint(fromScreen: screen.canvasBounds.cgRect.origin)
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

    /// Sets the camera as the user's choice, so it is saved.
    func change(to newCamera: Camera) {
        camera = newCamera
        onCameraChange?(newCamera)
    }
}
