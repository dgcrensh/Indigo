import AppKit
import DescriberCore
import QuartzCore

/// Renders a screen to an image for the PNG export (spec Section 11), with the canvas's own `RegionLayers` so the
/// image shows what the canvas does: the desk, the bounds as a rounded sheet with its shadow, the dashed viewport
/// line of a scrolling screen, regions with their titles, link and scroll indicators, tints on parts outside the
/// bounds, and the descriptions shown with `D`. Regions in scrolling content are drawn at their saved scroll positions
/// and clipped. Editing aids (selection, handles, grid) are left out, and the colors are always the light Paper
/// palette's, whatever the Mac uses.
@MainActor
enum ScreenImageRenderer {
    /// The screen's PNG at `scale` (1 for 1×, 2 for 2×), sized in points so its resolution is 72 dpi times the
    /// scale. Nil if the bitmap couldn't be made.
    static func pngData(for screen: Screen, in project: Project, scale: Int) -> Data? {
        guard let image = image(for: screen, in: project, scale: scale) else { return nil }
        let extent = ScreenImage.extent(of: screen, offsets: offsets(of: screen, in: project))
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = NSSize(width: extent.w, height: extent.h)
        return representation.representation(using: .png, properties: [:])
    }

    /// The screen's image at `scale`: its `ScreenImage.extent` in pixels times the scale.
    static func image(for screen: Screen, in project: Project, scale: Int) -> CGImage? {
        let offsets = offsets(of: screen, in: project)
        let extent = ScreenImage.extent(of: screen, offsets: offsets)
        let scale = max(scale, 1)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: extent.w * scale, height: extent.h * scale, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let root = layers(
            for: screen, extent: extent, offsets: offsets,
            visibleDescriptions: project.editorState.visibleDescriptions, scale: CGFloat(scale))
        // A layer's own `isGeometryFlipped` is relative to its superlayer, so the flipped root needs one above it.
        let frame = CALayer()
        frame.anchorPoint = .zero
        frame.frame = root.frame
        frame.addSublayer(root)
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        frame.render(in: context)
        CATransaction.commit()
        return context.makeImage()
    }

    private static func offsets(of screen: Screen, in project: Project) -> [RegionID: ScrollOffset] {
        project.editorState.screens[screen.id]?.scrollOffsets ?? [:]
    }

    /// The layer tree to render: a root the size of the extent with its geometry flipped, so it and its sublayers have
    /// their origin at the top left as on the canvas, holding the screen's layers moved so the extent's corner is at zero.
    private static func layers(
        for screen: Screen, extent: Frame, offsets: [RegionID: ScrollOffset], visibleDescriptions: Set<RegionID>,
        scale: CGFloat
    ) -> CALayer {
        let colors = CanvasColors(palette: .light)
        let root = CALayer()
        root.anchorPoint = .zero
        root.frame = CGRect(x: 0, y: 0, width: extent.w, height: extent.h)
        root.isGeometryFlipped = true
        root.backgroundColor = colors.desk

        let content = CALayer()
        content.anchorPoint = .zero
        content.frame = CGRect(x: -extent.x, y: -extent.y, width: extent.maxX, height: extent.maxY)
        root.addSublayer(content)

        let bounds = screen.canvasBounds
        let boundsLayer = CALayer()
        boundsLayer.anchorPoint = .zero
        boundsLayer.frame = bounds.cgRect
        boundsLayer.backgroundColor = colors.sheet
        boundsLayer.borderColor = colors.sheetBorder
        boundsLayer.borderWidth = 1
        let radius = CGFloat(
            min(PaperShapes.sheetCornerRadius(for: screen), Double(bounds.w) / 2, Double(bounds.h) / 2))
        boundsLayer.cornerRadius = radius
        boundsLayer.shadowColor = colors.sheetShadow
        boundsLayer.shadowOpacity = 1
        boundsLayer.shadowRadius = CGFloat(PaperShapes.shadowRadius)
        // The root's geometry is flipped, so a positive offset is downwards.
        boundsLayer.shadowOffset = CGSize(width: 0, height: PaperShapes.shadowOffset)
        boundsLayer.shadowPath = CGPath(
            roundedRect: boundsLayer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if screen.scroll != nil {
            let viewportOutline = CAShapeLayer()
            viewportOutline.anchorPoint = .zero
            viewportOutline.frame = boundsLayer.bounds
            viewportOutline.fillColor = nil
            viewportOutline.strokeColor = colors.viewportLine
            viewportOutline.lineWidth = 1
            viewportOutline.lineDashPattern = [4, 3]
            viewportOutline.path = CGPath(rect: screen.viewportFrame.cgRect, transform: nil)
            boundsLayer.addSublayer(viewportOutline)
        }
        content.addSublayer(boundsLayer)

        // One flat list of boxes in z-order, as on the canvas. `render(in:)` ignores masks, so a clipped region goes
        // in a container that clips to its bounds instead.
        let layout = ScrollLayout(screen: screen, offsets: offsets)
        let titleWidths = TitleWidths()
        for region in screen.allRegions {
            guard let drawn = layout.drawnFrame(of: region.id), let visible = layout.visibleFrame(of: region.id)
            else { continue }
            let layers = RegionLayers()
            layers.update(from: region, drawnFrame: drawn, bounds: bounds, titleWidths: titleWidths)
            layers.setScrollIndicators(layout.indicators(of: region.id))
            layers.apply(colors, scale: scale)
            layers.showsDescription = visibleDescriptions.contains(region.id)
            layers.layout(zoom: 1)
            guard visible != drawn else {
                content.addSublayer(layers.box)
                continue
            }
            let container = CALayer()
            container.anchorPoint = .zero
            container.frame = visible.cgRect
            container.masksToBounds = true
            layers.box.frame.origin = CGPoint(x: drawn.x - visible.x, y: drawn.y - visible.y)
            container.addSublayer(layers.box)
            content.addSublayer(container)
        }
        return root
    }
}
