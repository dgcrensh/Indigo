import AppKit
import DescriberCore
import QuartzCore

/// The layers that draw one region on the canvas: a box with the fill and border, the title, and a tint over each
/// part outside the canvas bounds. Frames are in zoomed screen coordinates (screen points × zoom).
final class RegionLayers {
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
    static let titleInset = CGSize(width: 4, height: 2)

    let box = CALayer()
    let title = CATextLayer()
    private var tints: [CALayer] = []
    private var frame = Frame(x: 0, y: 0, w: 0, h: 0)
    private var parts: [Frame] = []
    private var titleWidth: CGFloat = 0

    init() {
        box.anchorPoint = .zero
        box.borderWidth = 1
        title.anchorPoint = .zero
        title.font = Self.titleFont
        title.fontSize = Self.titleFont.pointSize
        title.truncationMode = .end
        title.isWrapped = false
        box.addSublayer(title)
    }

    /// Takes the region's title and frame, and the parts of it outside `bounds`.
    func update(from region: Region, bounds: Frame, titleWidths: TitleWidths) {
        frame = region.frame
        parts = bounds.contains(frame) ? [] : frame.parts(outside: bounds)
        if title.string as? String != region.title {
            title.string = region.title
        }
        titleWidth = titleWidths.width(of: region.title)
        while tints.count < parts.count {
            let tint = CALayer()
            tint.anchorPoint = .zero
            box.insertSublayer(tint, below: title)
            tints.append(tint)
        }
        while tints.count > parts.count {
            tints.removeLast().removeFromSuperlayer()
        }
    }

    func apply(_ colors: CanvasColors, scale: CGFloat) {
        box.backgroundColor = colors.regionFill
        box.borderColor = colors.regionBorder
        title.foregroundColor = colors.title
        title.contentsScale = scale
        for tint in tints {
            tint.backgroundColor = colors.outside
        }
    }

    /// Sizes the layers for `zoom`. A title that fits keeps its natural width, so zooming redraws only the titles
    /// whose truncation changes.
    func layout(zoom: Double) {
        box.frame = Self.zoomed(frame, zoom)
        for (tint, part) in zip(tints, parts) {
            tint.frame = Self.zoomed(part.offsetBy(dx: -frame.x, dy: -frame.y), zoom)
        }
        let inset = Self.titleInset
        let available = box.bounds.width - 2 * inset.width
        guard available >= 8, box.bounds.height >= Self.titleHeight + 2 * inset.height else {
            title.isHidden = true
            return
        }
        title.isHidden = false
        title.frame = CGRect(
            x: inset.width,
            y: inset.height,
            width: min(ceil(titleWidth), floor(available)),
            height: Self.titleHeight
        )
    }

    static func zoomed(_ frame: Frame, _ zoom: Double) -> CGRect {
        CGRect(
            x: Double(frame.x) * zoom, y: Double(frame.y) * zoom, width: Double(frame.w) * zoom,
            height: Double(frame.h) * zoom)
    }
}

/// Title widths measured once per string.
final class TitleWidths {
    private var widths: [String: CGFloat] = [:]

    func width(of title: String) -> CGFloat {
        if let width = widths[title] {
            return width
        }
        let width = (title as NSString).size(withAttributes: [.font: RegionLayers.titleFont]).width
        widths[title] = width
        return width
    }
}
