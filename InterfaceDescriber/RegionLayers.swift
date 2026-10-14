import AppKit
import DescriberCore
import QuartzCore

/// The layers that draw one region on the canvas: a box with the fill and border, the title, the description when it
/// is shown, a link indicator when the region has links, and a tint over each part outside the canvas bounds. Frames
/// are in zoomed screen coordinates (screen points × zoom).
final class RegionLayers {
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
    static let titleInset = CGSize(width: 4, height: 2)
    static let descriptionFont = NSFont.systemFont(ofSize: 10)
    /// The link indicator's side, in view points at every zoom, and the space between it and the title.
    static let linkIndicatorSize: CGFloat = 9
    static let linkIndicatorGap: CGFloat = 3

    let box = CALayer()
    let title = CATextLayer()
    /// The description, read-only, under the title. Only shown with `D` (spec Section 4).
    let descriptionText = CATextLayer()
    /// A small arrow out of the top-right corner, on regions with links (spec 8.4).
    let linkIndicator = CAShapeLayer()
    private var tints: [CALayer] = []
    private var frame = Frame(x: 0, y: 0, w: 0, h: 0)
    private var parts: [Frame] = []
    private var titleWidth: CGFloat = 0
    private var colors: CanvasColors?

    init() {
        box.anchorPoint = .zero
        box.borderWidth = 1
        title.anchorPoint = .zero
        title.font = Self.titleFont
        title.fontSize = Self.titleFont.pointSize
        title.truncationMode = .end
        title.isWrapped = false
        box.addSublayer(title)
        descriptionText.anchorPoint = .zero
        descriptionText.font = Self.descriptionFont
        descriptionText.fontSize = Self.descriptionFont.pointSize
        descriptionText.isWrapped = true
        descriptionText.truncationMode = .end
        descriptionText.masksToBounds = true
        descriptionText.isHidden = true
        box.addSublayer(descriptionText)
        linkIndicator.anchorPoint = .zero
        linkIndicator.fillColor = nil
        linkIndicator.lineWidth = 1.5
        linkIndicator.lineCap = .round
        linkIndicator.lineJoin = .round
        linkIndicator.path = Self.linkIndicatorPath
        linkIndicator.isHidden = true
        box.addSublayer(linkIndicator)
    }

    /// An arrow pointing up and to the right, in a square `linkIndicatorSize` on a side, with the origin at the top
    /// left.
    private static let linkIndicatorPath: CGPath = {
        let size = RegionLayers.linkIndicatorSize
        let inset: CGFloat = 1
        let path = CGMutablePath()
        path.move(to: CGPoint(x: inset, y: size - inset))
        path.addLine(to: CGPoint(x: size - inset, y: inset))
        path.move(to: CGPoint(x: size * 0.4, y: inset))
        path.addLine(to: CGPoint(x: size - inset, y: inset))
        path.addLine(to: CGPoint(x: size - inset, y: size * 0.6))
        return path
    }()

    /// Takes the region's title and frame, and the parts of it outside `bounds`.
    func update(from region: Region, bounds: Frame, titleWidths: TitleWidths) {
        if title.string as? String != region.title {
            title.string = region.title
        }
        titleWidth = titleWidths.width(of: region.title)
        let description = region.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if descriptionText.string as? String != description {
            descriptionText.string = description
        }
        hasDescription = !description.isEmpty
        hasLinks = !region.links.isEmpty
        setFrame(region.frame, bounds: bounds)
    }

    private var hasDescription = false
    private var hasLinks = false

    /// Whether the link indicator is drawn, for tests.
    var isShowingLinkIndicator: Bool {
        !linkIndicator.isHidden
    }

    /// Whether the description is shown on the canvas. Call `layout(zoom:)` afterwards.
    var showsDescription = false

    /// Whether the description layer is drawing text, for tests.
    var isShowingDescription: Bool {
        !descriptionText.isHidden
    }

    /// Draws the region at `frame`, its own or one a gesture previews. Call `layout(zoom:)` afterwards.
    func setFrame(_ frame: Frame, bounds: Frame) {
        self.frame = frame
        parts = bounds.contains(frame) ? [] : frame.parts(outside: bounds)
        while tints.count < parts.count {
            let tint = CALayer()
            tint.anchorPoint = .zero
            tint.backgroundColor = colors?.outside
            box.insertSublayer(tint, below: title)
            tints.append(tint)
        }
        while tints.count > parts.count {
            tints.removeLast().removeFromSuperlayer()
        }
    }

    /// Whether the region is selected, which draws its border in the accent color and thicker.
    var isSelected = false {
        didSet {
            if isSelected != oldValue { applyBorder() }
        }
    }

    func apply(_ colors: CanvasColors, scale: CGFloat) {
        self.colors = colors
        box.backgroundColor = colors.regionFill
        applyBorder()
        title.foregroundColor = colors.title
        title.contentsScale = scale
        descriptionText.foregroundColor = colors.description
        descriptionText.contentsScale = scale
        linkIndicator.strokeColor = colors.link
        linkIndicator.contentsScale = scale
        for tint in tints {
            tint.backgroundColor = colors.outside
        }
    }

    private func applyBorder() {
        box.borderColor = isSelected ? colors?.selection : colors?.regionBorder
        box.borderWidth = isSelected ? 2 : 1
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
        layoutLinkIndicator()
        guard available >= 8, box.bounds.height >= Self.titleHeight + 2 * inset.height else {
            title.isHidden = true
            descriptionText.isHidden = true
            return
        }
        // The title stops short of the link indicator.
        let indicatorSpace = linkIndicator.isHidden ? 0 : Self.linkIndicatorSize + Self.linkIndicatorGap
        title.isHidden = false
        title.frame = CGRect(
            x: inset.width,
            y: inset.height,
            width: max(min(ceil(titleWidth), floor(available - indicatorSpace)), 0),
            height: Self.titleHeight
        )
        layoutDescription(width: floor(available))
    }

    /// Puts the link indicator in the top-right corner, level with the title, when the region has links and is big
    /// enough to hold it.
    private func layoutLinkIndicator() {
        let size = Self.linkIndicatorSize
        let inset = Self.titleInset
        guard hasLinks, box.bounds.width >= size + 2 * inset.width, box.bounds.height >= size + 2 * inset.height else {
            linkIndicator.isHidden = true
            return
        }
        linkIndicator.isHidden = false
        let top = inset.height + max((Self.titleHeight - size) / 2, 0)
        linkIndicator.frame = CGRect(x: box.bounds.width - inset.width - size, y: top, width: size, height: size)
    }

    /// Puts the description under the title, wrapped to the region's width and clipped to its height.
    private func layoutDescription(width: CGFloat) {
        let top = Self.titleInset.height + Self.titleHeight
        let height = floor(box.bounds.height - top - Self.titleInset.height)
        let lineHeight = ceil(Self.descriptionFont.ascender - Self.descriptionFont.descender)
        guard showsDescription, hasDescription, height >= lineHeight else {
            descriptionText.isHidden = true
            return
        }
        descriptionText.isHidden = false
        descriptionText.frame = CGRect(x: Self.titleInset.width, y: top, width: width, height: height)
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
