import AppKit
import DescriberCore

/// Draws a screen the way the canvas shows it: the canvas bounds, the grid, and the regions with their titles and
/// the parts outside the bounds marked. Draws in view points into the current `NSGraphicsContext`, which must be
/// flipped. Line widths and title size stay the same at every zoom.
struct CanvasRenderer {
    var screen: Screen
    var camera: Camera
    /// The grid size to draw lines for, or nil for no grid.
    var gridSize: Int?

    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let titleInset = CGSize(width: 4, height: 2)

    /// Draws everything that falls in `dirtyRect`, in view points, and returns how many regions it drew.
    @discardableResult
    func draw(in dirtyRect: CGRect) -> Int {
        guard let context = NSGraphicsContext.current?.cgContext else { return 0 }
        context.saveGState()
        defer { context.restoreGState() }

        let bounds = screen.canvasBounds
        let boundsRect = camera.viewRect(fromScreen: bounds.cgRect)
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fill(boundsRect)

        if let gridSize {
            drawGrid(gridSize, in: dirtyRect, context: context)
        }

        context.setLineWidth(1)
        context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
        context.stroke(boundsRect.insetBy(dx: -0.5, dy: -0.5))
        if screen.scroll != nil {
            // Where the viewport ends inside the content area.
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(camera.viewRect(fromScreen: screen.viewportFrame.cgRect).insetBy(dx: 0.5, dy: 0.5))
            context.restoreGState()
        }

        return drawRegions(in: camera.screenRect(fromView: dirtyRect), bounds: bounds, context: context)
    }

    private func drawGrid(_ grid: Int, in dirtyRect: CGRect, context: CGContext) {
        let step = GridLines.drawnStep(grid: grid, zoom: camera.zoom)
        let visible = camera.screenRect(fromView: dirtyRect)
        let path = CGMutablePath()
        for x in GridLines.positions(from: visible.minX, to: visible.maxX, grid: step) {
            let viewX = camera.viewPoint(fromScreen: CGPoint(x: x, y: 0)).x
            path.move(to: CGPoint(x: viewX, y: dirtyRect.minY))
            path.addLine(to: CGPoint(x: viewX, y: dirtyRect.maxY))
        }
        for y in GridLines.positions(from: visible.minY, to: visible.maxY, grid: step) {
            let viewY = camera.viewPoint(fromScreen: CGPoint(x: 0, y: y)).y
            path.move(to: CGPoint(x: dirtyRect.minX, y: viewY))
            path.addLine(to: CGPoint(x: dirtyRect.maxX, y: viewY))
        }
        context.addPath(path)
        context.setLineWidth(0.5)
        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.4).cgColor)
        context.strokePath()
    }

    /// Draws the regions that intersect `visible` (in screen points) in z-order.
    private func drawRegions(in visible: CGRect, bounds: Frame, context: CGContext) -> Int {
        let fill = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
        let border = NSColor.secondaryLabelColor.cgColor
        let outside = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let titleHeight = ceil(Self.titleFont.ascender - Self.titleFont.descender + Self.titleFont.leading)
        let inset = Self.titleInset

        context.setLineWidth(1)
        var drawn = 0
        for region in screen.allRegions {
            let frame = region.frame.cgRect
            guard frame.intersects(visible) else { continue }
            drawn += 1
            let rect = camera.viewRect(fromScreen: frame)
            context.setFillColor(fill)
            context.fill(rect)
            let parts = region.frame.parts(outside: bounds)
            if !parts.isEmpty {
                context.setFillColor(outside)
                for part in parts {
                    context.fill(camera.viewRect(fromScreen: part.cgRect))
                }
            }
            context.setStrokeColor(border)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

            let titleRect = CGRect(
                x: rect.minX + inset.width,
                y: rect.minY + inset.height,
                width: rect.width - 2 * inset.width,
                height: titleHeight
            )
            if titleRect.width >= 8, rect.height >= titleHeight + 2 * inset.height {
                (region.title as NSString).draw(
                    with: titleRect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: attributes,
                    context: nil
                )
            }
        }
        return drawn
    }
}
