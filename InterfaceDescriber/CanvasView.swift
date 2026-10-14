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
    /// The region a two-finger scroll starting at `point` scrolls, or nil to pan the canvas (spec Section 5).
    func canvasScrollTarget(at point: CGPoint) -> RegionID?
    /// Scrolls `region`'s content by a scroll event's deltas, in view points.
    func canvasScroll(_ region: RegionID, byViewDX dx: Double, dy: Double)
}

/// The canvas. Each region is its own Core Animation layer, so panning moves one layer and zooming only resizes
/// layers; the milestone 4 spike found redrawing 500 regions with Core Graphics on every frame too slow. Turns
/// two-finger scrolls and pinches into camera changes, and passes clicks, drags, keys and scrolls over scrollable
/// regions to its `interaction`. Shows the selection, resize handles, and what a gesture in progress would do.
/// Regions are drawn where their scroll positions put them (`ScrollLayout`).
///
/// Only regions near the view are mounted: laid out for the zoom and in the layer tree (milestone 20). The rest wait
/// out of the tree until a pan or zoom brings them into the covered rect (`CanvasCoverage`), so the canvas does work
/// in proportion to what is on screen. Selected and previewed regions stay mounted wherever they are.
///
/// A zoom run, as a pinch or the details-panel zoom makes, is drawn with a transform (milestone 21): the mounted layers
/// stay laid out for the zoom the run began at (`layoutZoom`), and `regionsLayer` and the overlay are scaled to the
/// camera's zoom. When the run ends the regions are laid out for the final zoom at once, with their text clipped, and
/// the text is fitted over the next frames, nearest the view's center first.
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
                    if refreshCoverage() { updateMounts() }
                } else {
                    zoomChanged()
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
            selectedIDs = Set(selection)
            withoutAnimation(applySelection)
        }
    }
    /// The regions whose descriptions show on the canvas, from the editor state (spec Section 4).
    var visibleDescriptions: Set<RegionID> = [] {
        didSet {
            guard visibleDescriptions != oldValue else { return }
            withoutAnimation {
                for (id, layers) in zip(mountedIDs, mountedLayers) {
                    let shows = visibleDescriptions.contains(id)
                    if layers.showsDescription != shows {
                        layers.showsDescription = shows
                        layers.layout(zoom: layoutZoom)
                    }
                }
            }
        }
    }
    /// How far each scrolling region is scrolled, from the screen's editor state.
    var scrollOffsets: [RegionID: ScrollOffset] = [:] {
        didSet {
            guard scrollOffsets != oldValue else { return }
            withoutAnimation(applyScroll)
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
    /// The canvas bounds, drawn as a rounded sheet with a shadow, with the dashed viewport outline for a scrolling
    /// screen.
    private let boundsLayer = CALayer()
    private let viewportOutline = CAShapeLayer()
    /// The grid's dots, clipped to the view: one image of a row of dots, repeated down the view. A pan only moves the
    /// rows; the image is drawn again only when the spacing, the view's width, the color or the scale changes.
    private let gridLayer = CALayer()
    private let gridRows = CAReplicatorLayer()
    private let gridRow = CALayer()
    /// The image of one row of grid dots, and what it was drawn for, so it is only drawn again when that changes.
    private(set) var gridRowImage: CGImage?
    private var gridRowImageKey: GridRowImageKey?
    /// How the grid is tiled now, or nil while it is hidden.
    private var gridTiling: GridTiling?
    /// The regions' boxes in z-order, in zoomed screen coordinates; its position is the screen origin in the view.
    let regionsLayer = CALayer()
    /// Above the regions, in the same coordinates: the region being drawn, the marquee, and the resize handles.
    private let overlayLayer = CALayer()
    private let newRegionLayer = CAShapeLayer()
    private let marqueeLayer = CAShapeLayer()
    private let handleLayers = ResizeHandle.allCases.map { _ in CALayer() }
    /// A dashed outline of each selected scrolling region's whole content area, at its scroll position.
    private let contentOutline = CAShapeLayer()
    private let emptyLabel = CATextLayer()
    /// The layers of each region that has been mounted, made the first time it is and kept after that, so a region
    /// that scrolls back into view costs no rebuild.
    private var regionLayers: [RegionID: RegionLayers] = [:]
    /// The screen's regions by ID, as of the last reload.
    private var regions: [RegionID: Region] = [:]
    /// Where the screen's regions are drawn, as of the last reload or scroll.
    private(set) var scrollLayout: ScrollLayout?
    /// The part of the screen whose regions are mounted, in screen points.
    private var coverage: CanvasCoverage?
    /// The regions whose boxes are in `regionsLayer`, laid out for the zoom: those in the covered rect, plus the
    /// selection and any previewed regions. The others' layers, if they have any, are brought up to date when they
    /// mount.
    private var mounted: Set<RegionID> = []
    /// The draw-order positions of the mounted regions in `scrollLayout`, and their boxes as `regionsLayer` holds them.
    private var mountedPositions: [Int] = []
    private var mountedBoxes: [CALayer] = []
    /// The mounted regions and their layers in draw order, so a frame walks them without looking anything up.
    private var mountedIDs: [RegionID] = []
    private var mountedLayers: [RegionLayers] = []
    /// The draw-order positions of the regions with a visible part in `scrollLayout`, and the rect holding them all,
    /// so a camera whose covered rect holds them all mounts them without testing each one.
    private var visibleRegions: (positions: [Int], extent: CGRect)?
    /// `selection` as a set.
    private var selectedIDs: Set<RegionID> = []
    /// The drawn frames a gesture previews.
    private var previewFrames: [RegionID: Frame] = [:]
    /// Where the trackpad scroll in progress goes, chosen when it begins and kept through its momentum.
    private var scrollRoute: ScrollRoute?
    /// Whether a press started a gesture that hasn't been released yet.
    private var isTrackingGesture = false
    private let titleWidths = TitleWidths()
    /// The zoom the mounted regions and the overlay are laid out for. Outside a zoom run it is the camera's zoom;
    /// during one, the layers are scaled from it to the camera's zoom with a transform.
    private(set) var layoutZoom: Double = 1
    private var zoomRun = ZoomRun.idle
    /// When the zoom last changed. A change soon after another, outside a run begun by a gesture's phases, begins a
    /// timed run, and `settleTimer` ends it once the zoom has stayed put for `textSettleDelay`.
    private var lastZoomChange: CFTimeInterval = -.infinity
    private var settleTimer: Timer?
    /// How long the zoom stays put before a timed zoom run ends, in seconds.
    static let textSettleDelay: CFTimeInterval = 0.15
    /// How far a zoom run's transform may scale the layers before they are laid out again for the camera's zoom, so
    /// the picture never blurs badly.
    static let zoomRunScaleRange = 0.5...2.0
    /// The regions whose text waits to be fitted after a zoom run, farthest from the view's center first, so the next
    /// is at the end.
    private var textQueue: [RegionID] = []
    /// Fits the queued text a batch a frame: a display link while the window is on screen, a timer otherwise.
    private var textFitLink: CADisplayLink?
    private var textFitTimer: Timer?
    /// How long fitting queued text may take each frame, in seconds: about half a frame at 120 Hz.
    static let textFitBudget: CFTimeInterval = 0.004
    /// Whether the camera change under way is a single step, as a zoom command makes, rather than part of a run.
    private var isSteppingZoom = false
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
        layer?.backgroundColor = colors.desk
    }

    private func setUpLayers() {
        for layer in [stage, boundsLayer, viewportOutline, gridLayer, gridRows, gridRow, regionsLayer, overlayLayer] {
            layer.anchorPoint = .zero
        }
        for layer in [newRegionLayer, marqueeLayer] {
            layer.anchorPoint = .zero
            layer.lineWidth = 1
            layer.lineDashPattern = [4, 3]
            layer.isHidden = true
            overlayLayer.addSublayer(layer)
        }
        for layer in handleLayers {
            layer.anchorPoint = .zero
            layer.borderWidth = 1.5
            layer.cornerRadius = Self.handleSize / 2
            layer.isHidden = true
            overlayLayer.addSublayer(layer)
        }
        viewportOutline.fillColor = nil
        viewportOutline.lineWidth = 1
        viewportOutline.lineDashPattern = [4, 3]
        contentOutline.anchorPoint = .zero
        contentOutline.fillColor = nil
        contentOutline.lineWidth = 1
        contentOutline.lineDashPattern = [4, 3]
        overlayLayer.insertSublayer(contentOutline, at: 0)
        boundsLayer.borderWidth = 1
        boundsLayer.shadowOpacity = 1
        boundsLayer.shadowRadius = CGFloat(PaperShapes.shadowRadius)
        // The stage's geometry is flipped, so a positive offset is downwards.
        boundsLayer.shadowOffset = CGSize(width: 0, height: PaperShapes.shadowOffset)
        boundsLayer.addSublayer(viewportOutline)
        gridLayer.masksToBounds = true
        // The image's width is rounded up to whole pixels, so it is drawn at its own size rather than stretched.
        gridRow.contentsGravity = .left
        gridRows.addSublayer(gridRow)
        gridLayer.addSublayer(gridRows)
        gridLayer.isHidden = true
        emptyLabel.string = "No screen"
        emptyLabel.font = PaperFont.rounded(ofSize: 13, weight: .medium)
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
            withoutAnimation {
                coverage = nil
                refreshCoverage()
                updateMounts()
            }
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
        needsDisplay = true
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
        layer?.backgroundColor = colors.desk
        boundsLayer.backgroundColor = colors.sheet
        boundsLayer.borderColor = colors.sheetBorder
        boundsLayer.shadowColor = colors.sheetShadow
        viewportOutline.strokeColor = colors.viewportLine
        layoutGrid()
        emptyLabel.foregroundColor = colors.emptyText
        emptyLabel.contentsScale = scale
        for layers in regionLayers.values {
            layers.apply(colors, scale: scale)
        }
        appliedScale = scale
        for layer in [newRegionLayer, marqueeLayer] {
            layer.fillColor = colors.accentWash
            layer.strokeColor = colors.accent
        }
        for handle in handleLayers {
            handle.backgroundColor = colors.handleFill
            handle.borderColor = colors.accent
        }
        contentOutline.strokeColor = colors.scrollIndicator
    }

    /// The colors the canvas draws with now, for tests.
    var canvasColors: CanvasColors {
        colors
    }

    // MARK: Content

    /// The backing scale the region layers were last given, so a reload gives it to new layers and only re-applies it
    /// when it changed.
    private var appliedScale: CGFloat?

    /// Takes the screen as it is now, keeping the layers of regions that are still there, and brings the mounted
    /// regions up to date. Layers whose region didn't change are left alone, so an edit costs about what it changed;
    /// regions that aren't mounted are brought up to date when they mount.
    func reload() {
        withoutAnimation {
            emptyLabel.isHidden = screen != nil
            boundsLayer.isHidden = screen == nil
            if case .frames(let frames) = preview {
                previewFrames = frames
            } else {
                previewFrames = [:]
            }
            guard let screen else {
                regionLayers = [:]
                regions = [:]
                scrollLayout = nil
                mounted = []
                mountedPositions = []
                mountedBoxes = []
                mountedIDs = []
                mountedLayers = []
                visibleRegions = nil
                regionsLayer.sublayers = nil
                layoutGrid()
                layoutOverlay()
                return
            }
            let layout = ScrollLayout(screen: screen, offsets: scrollOffsets)
            self.scrollLayout = layout
            visibleRegions = nil
            var regions: [RegionID: Region] = [:]
            regions.reserveCapacity(layout.index.regions.count)
            for region in layout.index.regions {
                regions[region.id] = region
            }
            self.regions = regions
            if regionLayers.contains(where: { regions[$0.key] == nil }) {
                regionLayers = regionLayers.filter { regions[$0.key] != nil }
            }
            mounted.formIntersection(regions.keys)
            let scale = self.scale
            if scale != appliedScale {
                appliedScale = scale
                for layers in regionLayers.values {
                    layers.apply(colors, scale: scale)
                }
            }
            refreshCoverage()
            updateMounts(syncing: true)
            layoutContent()
            layoutGrid()
        }
    }

    /// Computes the covered rect again when there is none or the camera has left it. Returns whether it did.
    @discardableResult
    private func refreshCoverage() -> Bool {
        let size = bounds.size
        if let coverage, !coverage.needsRecompute(for: camera, viewSize: size) {
            return false
        }
        coverage = CanvasCoverage(camera: camera, viewSize: size)
        return true
    }

    /// Mounts the regions in the covered rect, the selection and the previewed regions, and unmounts the rest. A
    /// region that mounts is brought up to date and laid out for the zoom; with `syncing`, as after the screen or its
    /// scroll positions changed, regions that stay mounted are brought up to date too. Sets the boxes in draw order,
    /// only when the list changed.
    private func updateMounts(syncing: Bool = false) {
        guard let layout = scrollLayout, let coverage else { return }
        let positions = mountPositions(layout, coverage)
        // Most camera changes mount and unmount nothing.
        if !syncing, positions == mountedPositions { return }
        let zoom = layoutZoom
        var mounting: Set<RegionID> = []
        mounting.reserveCapacity(positions.count)
        var boxes: [CALayer] = []
        boxes.reserveCapacity(positions.count)
        var ids: [RegionID] = []
        ids.reserveCapacity(positions.count)
        var mountedLayers: [RegionLayers] = []
        mountedLayers.reserveCapacity(positions.count)
        for position in positions {
            let id = layout.index.regions[position].id
            let layers: RegionLayers
            if !syncing, mounted.contains(id), let existing = regionLayers[id] {
                layers = existing
            } else {
                guard let prepared = prepare(id) else { continue }
                layers = prepared
                if !mounted.contains(id) {
                    layers.layoutIfNeeded(zoom: zoom)
                }
            }
            mounting.insert(id)
            boxes.append(layers.box)
            ids.append(id)
            mountedLayers.append(layers)
        }
        mounted = mounting
        mountedIDs = ids
        self.mountedLayers = mountedLayers
        mountedPositions = positions
        setMountedBoxes(boxes, keepsOrder: !syncing)
    }

    /// The draw-order positions to mount: the regions in the covered rect, the selection and the previewed regions.
    private func mountPositions(_ layout: ScrollLayout, _ coverage: CanvasCoverage) -> [Int] {
        let visible = visibleRegions ?? layout.visibleRegions()
        visibleRegions = visible
        let covered =
            coverage.covered.contains(visible.extent)
            ? visible.positions : layout.regions(intersecting: coverage.covered)
        var extra: [Int] = []
        for id in selection {
            if let position = layout.index.position(of: id) { extra.append(position) }
        }
        for id in previewFrames.keys {
            if let position = layout.index.position(of: id) { extra.append(position) }
        }
        guard !extra.isEmpty else { return covered }
        return Array(Set(covered).union(extra)).sorted()
    }

    /// Puts `boxes` in `regionsLayer` in that order. With `keepsOrder`, the boxes that stay are known to keep their
    /// order, so only the boxes that come and go are removed and inserted, unless that is most of them; otherwise the
    /// sublayers are set, which removes and re-adds every box, only when the list changed.
    private func setMountedBoxes(_ boxes: [CALayer], keepsOrder: Bool) {
        defer { mountedBoxes = boxes }
        guard keepsOrder else {
            if !mountedBoxes.elementsEqual(boxes, by: ===) {
                regionsLayer.sublayers = boxes
            }
            return
        }
        let incoming = Set(boxes.map(ObjectIdentifier.init))
        let kept = mountedBoxes.filter { incoming.contains(ObjectIdentifier($0)) }
        let changes = (mountedBoxes.count - kept.count) + (boxes.count - kept.count)
        if changes > boxes.count / 2 {
            regionsLayer.sublayers = boxes
            return
        }
        for box in mountedBoxes where !incoming.contains(ObjectIdentifier(box)) {
            box.removeFromSuperlayer()
        }
        var next = 0
        for (index, box) in boxes.enumerated() {
            if next < kept.count, kept[next] === box {
                next += 1
            } else {
                regionsLayer.insertSublayer(box, at: UInt32(index))
            }
        }
    }

    /// `id`'s layers, made if it has none, brought up to date with the region, where it is drawn (at its previewed
    /// frame while a gesture previews one), its scroll state, selection and description. Not laid out or mounted.
    @discardableResult
    private func prepare(_ id: RegionID) -> RegionLayers? {
        guard let screen, let layout = scrollLayout, let region = regions[id],
            let drawn = layout.drawn(id, previewing: previewFrames)
        else { return nil }
        let layers: RegionLayers
        if let existing = regionLayers[id] {
            layers = existing
        } else {
            layers = RegionLayers()
            layers.apply(colors, scale: appliedScale ?? scale)
            regionLayers[id] = layers
        }
        layers.update(from: region, drawnFrame: drawn.frame, bounds: screen.canvasBounds, titleWidths: titleWidths)
        layers.setClip(drawn.clip)
        layers.setScrollIndicators(layout.indicators(of: id))
        layers.isSelected = selectedIDs.contains(id)
        layers.showsDescription = visibleDescriptions.contains(id)
        return layers
    }

    /// `id`'s layers laid out for the zoom, mounted or not, for tests. Makes them for a region that has none, without
    /// mounting it.
    private func laidOutLayers(_ id: RegionID) -> RegionLayers? {
        if mounted.contains(id) {
            return regionLayers[id]
        }
        var layers: RegionLayers?
        withoutAnimation {
            layers = prepare(id)
            layers?.layoutIfNeeded(zoom: layoutZoom)
        }
        return layers
    }

    /// The IDs of the regions whose laid-out layers pass `test`, mounted or not, for tests.
    private func layerIDs(where test: (RegionLayers) -> Bool) -> Set<RegionID> {
        Set(regions.keys.filter { laidOutLayers($0).map(test) ?? false })
    }

    /// The fill of `id`'s box, for tests. Nil for an unfilled region.
    func fillColor(of id: RegionID) -> CGColor? {
        laidOutLayers(id)?.fillColor
    }

    /// The corner radius of `id`'s box in view points, for tests.
    func cornerRadius(of id: RegionID) -> CGFloat? {
        laidOutLayers(id)?.cornerRadius
    }

    /// The sheet's corner radius in view points, for tests.
    var sheetCornerRadius: CGFloat {
        boundsLayer.cornerRadius
    }

    /// The number of regions on the screen: each has layers, or will when it first mounts.
    var regionLayerCount: Int {
        regions.count
    }

    /// The number of regions whose boxes are in the layer tree.
    var mountedRegionCount: Int {
        mounted.count
    }

    /// The regions whose boxes are in the layer tree, for tests.
    var mountedRegionIDs: Set<RegionID> {
        mounted
    }

    /// The regions whose boxes are in the layer tree, in z-order, for tests.
    var mountedRegionOrder: [RegionID] {
        let ids = Dictionary(uniqueKeysWithValues: regionLayers.map { (ObjectIdentifier($0.value.box), $0.key) })
        return (regionsLayer.sublayers ?? []).compactMap { ids[ObjectIdentifier($0)] }
    }

    /// Draws the regions where the new scroll positions put them. Mounted regions are brought up to date, and only
    /// the layers that moved are laid out again.
    private func applyScroll() {
        guard let screen else { return }
        scrollLayout = ScrollLayout(screen: screen, offsets: scrollOffsets)
        visibleRegions = nil
        updateMounts(syncing: true)
        let zoom = layoutZoom
        for layers in mountedLayers {
            layers.layoutIfNeeded(zoom: zoom)
        }
        layoutOverlay()
    }

    /// Where `id` is drawn, for tests.
    func drawnFrame(of id: RegionID) -> Frame? {
        laidOutLayers(id)?.drawnFrame
    }

    /// Whether `id` is scrolled out of view, for tests.
    func isClippedAway(_ id: RegionID) -> Bool {
        laidOutLayers(id)?.isClippedAway ?? false
    }

    /// How many scroll indicators `id` draws, for tests.
    func scrollIndicatorCount(of id: RegionID) -> Int {
        laidOutLayers(id)?.scrollIndicatorCount ?? 0
    }

    /// Whether the dashed content outline is showing, for tests.
    var showsContentOutline: Bool {
        !contentOutline.isHidden
    }

    /// Lays out for a new zoom. Outside a zoom run the regions are laid out for it and their text fitted at once. A
    /// change soon after another begins a timed run, unless it is a zoom command's step. During a run nothing is laid
    /// out: the transform scales the layers, until it strays out of `zoomRunScaleRange` and the run rebases.
    private func zoomChanged() {
        let now = CACurrentMediaTime()
        let follows = now - lastZoomChange < Self.textSettleDelay
        lastZoomChange = now
        if isSteppingZoom {
            abandonZoomRun()
        } else if zoomRun == .idle, follows {
            stopFittingText()
            zoomRun = .timed
        }
        if zoomRun == .timed {
            scheduleTimedRunEnd()
        }
        refreshCoverage()
        guard zoomRun != .idle else {
            stopFittingText()
            layoutZoom = camera.zoom
            updateMounts()
            layoutContent()
            return
        }
        if Self.zoomRunScaleRange.contains(camera.zoom / layoutZoom) {
            updateMounts()
        } else {
            // Rebase: the mounted regions are laid out for the camera's zoom, their text clipped, and the transform
            // goes back to 1.
            layoutZoom = camera.zoom
            updateMounts()
            for layers in mountedLayers {
                layers.layoutIfNeeded(zoom: layoutZoom, fitsText: false)
            }
            layoutOverlay()
        }
        layoutSheet()
        positionContent()
    }

    /// Begins a zoom run, as a pinch's first event and the details-panel zoom do. Until `endZoomRun()`, zoom changes
    /// scale the laid-out layers with a transform rather than laying them out, and any text waiting to be fitted waits
    /// for the run to end.
    func beginZoomRun() {
        settleTimer?.invalidate()
        settleTimer = nil
        stopFittingText()
        zoomRun = .explicit
    }

    /// Ends the zoom run under way: lays the mounted regions out for the camera's zoom with their text clipped and
    /// removes the transform, so everything is where it belongs at once, then fits the text over the next frames,
    /// within `textFitBudget` a frame, nearest the view's center first.
    func endZoomRun() {
        guard zoomRun != .idle else { return }
        finishZoomRun()
        let center = camera.screenPoint(fromView: CGPoint(x: bounds.midX, y: bounds.midY))
        var waiting: [(id: RegionID, distance: Double)] = []
        for (id, layers) in zip(mountedIDs, mountedLayers) where !layers.isTextFitted {
            let frame = layers.drawnFrame
            let dx = Double(frame.x) + Double(frame.w) / 2 - Double(center.x)
            let dy = Double(frame.y) + Double(frame.h) / 2 - Double(center.y)
            waiting.append((id, dx * dx + dy * dy))
        }
        textQueue = waiting.sorted { $0.distance > $1.distance }.map(\.id)
        if !textQueue.isEmpty {
            startFittingText()
        }
    }

    /// Ends the zoom run's transform: lays the mounted regions and the overlay out for the camera's zoom, text clipped.
    private func finishZoomRun() {
        abandonZoomRun()
        withoutAnimation {
            layoutZoom = camera.zoom
            for layers in mountedLayers {
                layers.layoutIfNeeded(zoom: layoutZoom, fitsText: false)
            }
            layoutOverlay()
            positionContent()
        }
    }

    /// Forgets the zoom run under way without laying anything out, as a zoom command does before laying out itself.
    private func abandonZoomRun() {
        zoomRun = .idle
        settleTimer?.invalidate()
        settleTimer = nil
    }

    /// Ends the timed run once the zoom has stayed put for `textSettleDelay`, checking again if it moved since.
    private func scheduleTimedRunEnd() {
        guard settleTimer == nil else { return }
        let timer = Timer(timeInterval: Self.textSettleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.settleTimer = nil
                guard self.zoomRun == .timed else { return }
                if CACurrentMediaTime() - self.lastZoomChange < Self.textSettleDelay {
                    self.scheduleTimedRunEnd()
                } else {
                    self.endZoomRun()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func startFittingText() {
        guard textFitLink == nil, textFitTimer == nil else { return }
        if window?.isVisible == true {
            let link = displayLink(target: self, selector: #selector(fitTextOnFrame(_:)))
            link.add(to: .main, forMode: .common)
            textFitLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.fitQueuedText()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            textFitTimer = timer
        }
    }

    @objc private func fitTextOnFrame(_ link: CADisplayLink) {
        fitQueuedText()
    }

    /// Fits the queued regions' text, nearest the view's center first, until `budget` seconds have passed. Regions
    /// that unmounted since are skipped: they are fitted when they mount. Returns whether any text is left to fit.
    @discardableResult
    func fitQueuedText(budget: CFTimeInterval = textFitBudget) -> Bool {
        let start = CACurrentMediaTime()
        withoutAnimation {
            while let id = textQueue.popLast() {
                if mounted.contains(id), let layers = regionLayers[id] {
                    layers.layoutIfNeeded(zoom: layoutZoom)
                }
                if CACurrentMediaTime() - start >= budget { break }
            }
        }
        if textQueue.isEmpty {
            stopFittingText()
        }
        return !textQueue.isEmpty
    }

    /// Drops the text waiting to be fitted and stops fitting it.
    private func stopFittingText() {
        textQueue = []
        textFitLink?.invalidate()
        textFitLink = nil
        textFitTimer?.invalidate()
        textFitTimer = nil
    }

    /// Ends any zoom run and fits all the mounted region text at once, as a zoom command and tests want. Regions that
    /// aren't mounted are fitted when they mount.
    func settleText() {
        if zoomRun != .idle {
            finishZoomRun()
        }
        stopFittingText()
        withoutAnimation {
            for layers in mountedLayers where !layers.isTextFitted {
                layers.layout(zoom: layoutZoom)
            }
        }
    }

    /// Whether every region's text is fitted to the zoom, for tests: no zoom run is under way and no text waits to be
    /// fitted. A region that isn't mounted is fitted when it mounts or a test asks about it.
    var isTextSettled: Bool {
        zoomRun == .idle && textQueue.isEmpty && mountedLayers.allSatisfy(\.isTextFitted)
    }

    /// Whether a zoom run is under way, for tests.
    var isInZoomRun: Bool {
        zoomRun != .idle
    }

    /// The scale the zoom run's transform gives the regions, for tests: 1 outside a run.
    var zoomRunScale: CGFloat {
        regionsLayer.transform.m11
    }

    /// Moves to `newCamera` in one step, as a zoom command does: ends any zoom run, lays out for the new zoom and fits
    /// the text at once. The next change doesn't count as following this one, so it doesn't begin a timed run.
    func step(to newCamera: Camera) {
        isSteppingZoom = true
        change(to: newCamera)
        isSteppingZoom = false
        lastZoomChange = -.infinity
    }

    /// Lays the mounted regions out for `layoutZoom`, fitting their text, and the sheet for the camera's zoom, then
    /// positions everything. Regions laid out for this zoom with nothing changed since are skipped.
    private func layoutContent() {
        guard screen != nil else { return }
        layoutSheet()
        let zoom = layoutZoom
        for layers in mountedLayers {
            layers.layoutIfNeeded(zoom: zoom)
        }
        layoutOverlay()
        positionContent()
    }

    /// Sizes the sheet and the viewport outline for the camera's zoom. They are one layer each, so they are laid out
    /// for every zoom change, in a run or not.
    private func layoutSheet() {
        guard let screen else { return }
        let zoom = camera.zoom
        boundsLayer.bounds = CGRect(origin: .zero, size: RegionLayers.zoomed(screen.canvasBounds, zoom).size)
        let radius = min(
            CGFloat(PaperShapes.sheetCornerRadius(for: screen) * zoom), boundsLayer.bounds.width / 2,
            boundsLayer.bounds.height / 2)
        boundsLayer.cornerRadius = radius
        boundsLayer.shadowPath = CGPath(
            roundedRect: boundsLayer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if screen.scroll != nil {
            viewportOutline.isHidden = false
            viewportOutline.path = CGPath(rect: RegionLayers.zoomed(screen.viewportFrame, zoom), transform: nil)
        } else {
            viewportOutline.isHidden = true
        }
    }

    /// Moves the content for the camera's pan, and scales the regions and the overlay from `layoutZoom` to the
    /// camera's zoom. Nothing is resized or redrawn.
    private func positionContent() {
        let origin = camera.viewPoint(fromScreen: .zero)
        regionsLayer.position = origin
        overlayLayer.position = origin
        let scale = CGFloat(camera.zoom / layoutZoom)
        let transform = scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1)
        if !CATransform3DEqualToTransform(regionsLayer.transform, transform) {
            regionsLayer.transform = transform
            overlayLayer.transform = transform
        }
        if let screen {
            boundsLayer.position = camera.viewPoint(fromScreen: screen.canvasBounds.cgRect.origin)
        }
    }

    // MARK: Selection and previews

    /// The regions whose layers show as selected, for tests.
    var selectedLayerIDs: Set<RegionID> {
        layerIDs { $0.isSelected }
    }

    /// The regions whose layers are drawing a description, for tests.
    var describedLayerIDs: Set<RegionID> {
        layerIDs { $0.isShowingDescription }
    }

    /// The regions whose layers are drawing the link indicator, for tests.
    var linkedLayerIDs: Set<RegionID> {
        layerIDs { $0.isShowingLinkIndicator }
    }

    /// Whether the resize handles are showing, for tests.
    var showsHandles: Bool {
        !handleLayers[0].isHidden
    }

    private func applySelection() {
        for (id, layers) in zip(mountedIDs, mountedLayers) {
            layers.isSelected = selectedIDs.contains(id)
        }
        updateMounts()
        layoutHandles()
        layoutContentOutline()
    }

    private func applyPreview() {
        if case .frames(let frames) = preview {
            showPreviewFrames(frames)
        } else {
            showPreviewFrames([:])
        }
        layoutOverlay()
    }

    /// Draws the regions in `frames` (drawn frames) at those frames, keeping them mounted, and every other region that
    /// had a previewed frame where it is drawn.
    private func showPreviewFrames(_ frames: [RegionID: Frame]) {
        guard scrollLayout != nil else { return }
        let changed = Set(previewFrames.keys).union(frames.keys)
        previewFrames = frames
        updateMounts()
        let zoom = layoutZoom
        for id in changed where mounted.contains(id) {
            prepare(id)?.layoutIfNeeded(zoom: zoom)
        }
    }

    /// Lays out the region being drawn, the marquee and the handles for the camera's zoom.
    private func layoutOverlay() {
        let zoom = layoutZoom
        switch preview {
        case .newRegion(let frame):
            Self.outline(newRegionLayer, RegionLayers.zoomed(frame, zoom))
            marqueeLayer.isHidden = true
        case .marquee(let rect):
            Self.outline(
                marqueeLayer,
                CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom))
            newRegionLayer.isHidden = true
        case .none, .frames:
            newRegionLayer.isHidden = true
            marqueeLayer.isHidden = true
        }
        layoutHandles()
        layoutContentOutline()
    }

    /// Shows a dashed outline layer around `rect`.
    private static func outline(_ layer: CAShapeLayer, _ rect: CGRect) {
        layer.isHidden = false
        layer.frame = rect
        layer.path = CGPath(rect: CGRect(origin: .zero, size: rect.size).insetBy(dx: 0.5, dy: 0.5), transform: nil)
    }

    /// Outlines the content area of each selected scrolling region, except while a gesture moves or resizes regions.
    private func layoutContentOutline() {
        let path = CGMutablePath()
        if let layout = scrollLayout, case .none = preview {
            for id in selection where regions[id]?.scroll != nil {
                guard layout.visibleFrame(of: id) != nil, let area = layout.drawnContentArea(of: id) else { continue }
                path.addRect(RegionLayers.zoomed(area, layoutZoom))
            }
        }
        contentOutline.isHidden = path.isEmpty
        contentOutline.path = path.isEmpty ? nil : path
    }

    /// The frame the handles go around: the single selected region's, while the Select tool is active.
    private var handleFrame: Frame? {
        guard tool == .select, selection.count == 1, let id = selection.first, let region = regions[id] else {
            return nil
        }
        if case .frames(let frames) = preview, let frame = frames[id] {
            return frame
        }
        return scrollLayout?.drawnFrame(of: id) ?? region.frame
    }

    /// The handles' diameter, in view points, at every zoom.
    static let handleSize: CGFloat = 8

    /// The handles' corner radius, for tests: half their size, as circles.
    var handleCornerRadius: CGFloat {
        handleLayers[0].cornerRadius
    }

    private func layoutHandles() {
        guard let frame = handleFrame else {
            for handle in handleLayers {
                handle.isHidden = true
            }
            return
        }
        let rect = RegionLayers.zoomed(frame, layoutZoom)
        let size = Self.handleSize
        for (handle, layer) in zip(ResizeHandle.allCases, handleLayers) {
            let center = handle.point(on: rect)
            layer.isHidden = false
            layer.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        }
    }

    /// The grid dots' diameter and the least space between them, in view points.
    static let gridDotSize: CGFloat = 2
    static let gridDotMinimumSpacing = 10.0

    /// Whether the grid's dots are showing, for tests.
    var showsGridDots: Bool {
        !gridLayer.isHidden && gridDotCount > 0
    }

    /// How many grid dots are drawn, including the ones just outside the view, for tests.
    var gridDotCount: Int {
        guard !gridLayer.isHidden, let gridTiling else { return 0 }
        return gridTiling.columns * gridTiling.rows
    }

    /// Tiles the grid's dots over the view, starting from the last line before its top-left corner. A pan changes
    /// only where the rows start; a zoom, a resize, a new color or a new scale also draws the row image again.
    private func layoutGrid() {
        guard screen != nil, let gridSize,
            let tiling = GridTiling(
                grid: gridSize, camera: camera, viewSize: bounds.size, minimumSpacing: Self.gridDotMinimumSpacing)
        else {
            gridTiling = nil
            gridLayer.isHidden = true
            return
        }
        gridTiling = tiling
        let size = Self.gridDotSize
        let spacing = CGFloat(tiling.spacing)
        let rowWidth = CGFloat(tiling.columns - 1) * spacing + size
        let key = GridRowImageKey(spacing: tiling.spacing, columns: tiling.columns, color: colors.gridDot, scale: scale)
        if key != gridRowImageKey {
            gridRowImage = Self.gridRowImage(
                columns: tiling.columns, spacing: spacing, color: colors.gridDot, scale: scale)
            gridRow.contents = gridRowImage
            gridRow.contentsScale = scale
            gridRowImageKey = key
        }
        gridLayer.isHidden = false
        gridLayer.frame = CGRect(origin: .zero, size: bounds.size)
        // Each dot is centered on its line, so the row starts half a dot before the first one.
        gridRow.frame = CGRect(x: -size / 2, y: -size / 2, width: rowWidth, height: size)
        gridRows.frame = CGRect(
            x: tiling.originX, y: tiling.originY, width: Double(rowWidth), height: Double(tiling.rows) * tiling.spacing)
        gridRows.instanceCount = tiling.rows
        gridRows.instanceTransform = CATransform3DMakeTranslation(0, spacing, 0)
    }

    /// A row of `columns` dots `gridDotSize` across and `spacing` apart, with no margin around them.
    private static func gridRowImage(columns: Int, spacing: CGFloat, color: CGColor, scale: CGFloat) -> CGImage? {
        let size = gridDotSize
        let width = CGFloat(columns - 1) * spacing + size
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int((width * scale).rounded(.up)), height: Int((size * scale).rounded(.up)),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(color)
        for column in 0..<columns {
            context.fillEllipse(in: CGRect(x: CGFloat(column) * spacing, y: 0, width: size, height: size))
        }
        return context.makeImage()
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    // MARK: Gestures

    private enum ScrollRoute {
        case canvas
        case region(RegionID)
    }

    /// Two-finger scroll over a selected scrollable region scrolls it; anywhere else it pans (spec Section 5). A
    /// trackpad scroll keeps the target it began with through its momentum; each mouse wheel step chooses again.
    override func scrollWheel(with event: NSEvent) {
        guard screen != nil else {
            super.scrollWheel(with: event)
            return
        }
        // A mouse wheel reports lines rather than points.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let begins = event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if begins || scrollRoute == nil {
            scrollRoute = interaction?.canvasScrollTarget(at: screenPoint(of: event)).map(ScrollRoute.region) ?? .canvas
        }
        scroll(byViewDX: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale)
    }

    /// Scrolls the region the current scroll goes to, or pans.
    private func scroll(byViewDX dx: Double, dy: Double) {
        if case .region(let region) = scrollRoute {
            interaction?.canvasScroll(region, byViewDX: dx, dy: dy)
        } else {
            change(to: camera.panned(byViewDX: dx, dy: dy))
        }
    }

    /// A scroll beginning at `point`, in screen points, by `dx`, `dy` view points, as a trackpad gesture's first
    /// event does. For tests.
    func simulateScroll(at point: CGPoint, dx: Double, dy: Double) {
        scrollRoute = interaction?.canvasScrollTarget(at: point).map(ScrollRoute.region) ?? .canvas
        scroll(byViewDX: dx, dy: dy)
    }

    override func magnify(with event: NSEvent) {
        guard screen != nil else { return }
        if event.phase == .began {
            beginZoomRun()
        }
        let anchor = convert(event.locationInWindow, from: nil)
        change(to: camera.zoomed(to: camera.zoom * (1 + event.magnification), anchor: anchor))
        if event.phase == .ended || event.phase == .cancelled {
            endZoomRun()
        }
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

/// Whether the canvas is in a zoom run, and how it began.
private enum ZoomRun {
    case idle
    /// Begun by `beginZoomRun()`, as a pinch's first event or the details-panel zoom does, and ended by `endZoomRun()`.
    case explicit
    /// Begun by a zoom change soon after another, and ended once the zoom stays put for `textSettleDelay`.
    case timed
}

/// What the grid's row image was drawn for.
private struct GridRowImageKey: Equatable {
    var spacing: Double
    var columns: Int
    var color: CGColor
    var scale: CGFloat
}
