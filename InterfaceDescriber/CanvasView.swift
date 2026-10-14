import AppKit
import DescriberCore

/// The canvas: draws the active screen through `CanvasRenderer` and turns two-finger scrolls and pinches into
/// camera changes. Tools and clicks arrive in milestone 5.
final class CanvasView: NSView {
    var screen: Screen? {
        didSet { needsDisplay = true }
    }
    var camera = Camera() {
        didSet {
            if camera != oldValue { needsDisplay = true }
        }
    }
    /// The grid size to draw, or nil to hide the grid.
    var gridSize: Int? {
        didSet {
            if gridSize != oldValue { needsDisplay = true }
        }
    }
    /// Titles laid out in earlier draws.
    let titleCache = TitleCache()
    /// Called after a gesture or a zoom command changes the camera, so it can be saved.
    var onCameraChange: ((Camera) -> Void)?
    /// Called after the view changes size.
    var onResize: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { onResize?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let screen else {
            drawNoScreen()
            return
        }
        CanvasRenderer(screen: screen, camera: camera, gridSize: gridSize, titles: titleCache).draw(in: dirtyRect)
    }

    private func drawNoScreen() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = "No screen" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
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
