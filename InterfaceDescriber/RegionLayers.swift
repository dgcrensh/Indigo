import AppKit
import DescriberCore
import QuartzCore

/// The layers that draw one region on the canvas: a rounded box with its kind family's fill and border, the title, the
/// description when it is shown, a link indicator when the region has links, scroll indicators when it scrolls, and a
/// tint over each part outside the canvas bounds. Inside scrolling content the box is masked to its clip. Frames are drawn frames
/// (`ScrollLayout`), in zoomed screen coordinates (screen points × zoom).
///
/// The layers remember what they were last laid out for, so `layoutIfNeeded(zoom:)` skips a region nothing changed
/// on. When a zoom run rebases or ends, `layout(zoom:fitsText:)` can keep the text layers' sizes and clip them instead
/// of re-truncating and redrawing their text, which the canvas then fits a few regions a frame.
final class RegionLayers {
    static let titleFont = PaperFont.rounded(ofSize: 11, weight: .semibold)
    static let titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
    static let titleInset = CGSize(width: 4, height: 2)
    static let descriptionFont = PaperFont.rounded(ofSize: 10)
    /// The link indicator's diameter, its inset from the box's top-right corner, and the space between it and the
    /// title, in view points at every zoom.
    static let linkIndicatorSize: CGFloat = 8
    static let linkIndicatorInset: CGFloat = 6
    static let linkIndicatorGap: CGFloat = 3
    /// The scroll indicators' thickness and their inset from the box's edges, in view points at every zoom.
    static let scrollIndicatorThickness: CGFloat = 3
    static let scrollIndicatorInset: CGFloat = 2

    let box = CALayer()
    /// Clips the title and the description to the inside of the box, so their text can keep its size while the zoom
    /// changes.
    let textClip = CALayer()
    let title = CATextLayer()
    /// The description, read-only, under the title. Only shown with `D` (spec Section 4).
    let descriptionText = CATextLayer()
    /// A small accent dot near the top-right corner, on regions with links (spec 8.4).
    let linkIndicator = CALayer()
    private var tints: [CALayer] = []
    /// Masks the box to its clip inside scrolling content.
    private let clipMask = CALayer()
    private var clip: Frame?
    private var indicators: [ScrollLayout.Indicator] = []
    private var indicatorLayers: [CALayer] = []
    private var frame = Frame(x: 0, y: 0, w: 0, h: 0)
    private var parts: [Frame] = []
    private var titleWidth: CGFloat = 0
    private var colors: CanvasColors?
    private var kind: RegionKind = .open
    /// Whether something the layout depends on changed since the last `layout(zoom:)`.
    private(set) var needsLayout = true
    /// The zoom of the last layout, and whether it fitted the text to it.
    private var laidOutZoom: Double?
    private var textFitted = false

    init() {
        box.anchorPoint = .zero
        box.borderWidth = 1
        textClip.anchorPoint = .zero
        textClip.masksToBounds = true
        box.addSublayer(textClip)
        title.anchorPoint = .zero
        title.font = Self.titleFont
        title.fontSize = Self.titleFont.pointSize
        title.truncationMode = .end
        title.isWrapped = false
        textClip.addSublayer(title)
        descriptionText.anchorPoint = .zero
        descriptionText.font = Self.descriptionFont
        descriptionText.fontSize = Self.descriptionFont.pointSize
        descriptionText.isWrapped = true
        descriptionText.truncationMode = .end
        descriptionText.masksToBounds = true
        descriptionText.isHidden = true
        textClip.addSublayer(descriptionText)
        linkIndicator.anchorPoint = .zero
        linkIndicator.cornerRadius = Self.linkIndicatorSize / 2
        linkIndicator.isHidden = true
        box.addSublayer(linkIndicator)
        clipMask.anchorPoint = .zero
        clipMask.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    /// Takes the region's title, the frame it is drawn at, and the parts of that outside `bounds`.
    func update(from region: Region, drawnFrame: Frame, bounds: Frame, titleWidths: TitleWidths) {
        // Compared with the strings last given, kept in Swift, so an unchanged region costs no bridging or trimming.
        if region.title != shownTitle {
            shownTitle = region.title
            title.string = region.title
            titleWidth = titleWidths.width(of: region.title)
            needsLayout = true
        }
        if region.description != shownDescription {
            shownDescription = region.description
            let description = region.description.trimmingCharacters(in: .whitespacesAndNewlines)
            descriptionText.string = description
            if hasDescription != !description.isEmpty {
                hasDescription = !description.isEmpty
                needsLayout = true
            }
        }
        if hasLinks != !region.links.isEmpty {
            hasLinks = !region.links.isEmpty
            needsLayout = true
        }
        if region.kind != kind {
            kind = region.kind
            applyFamily()
        }
        setFrame(drawnFrame, bounds: bounds)
    }

    private var hasDescription = false
    private var hasLinks = false
    /// The title and the untrimmed description the text layers were last given.
    private var shownTitle: String?
    private var shownDescription: String?

    /// Whether the link indicator is drawn, for tests.
    var isShowingLinkIndicator: Bool {
        !linkIndicator.isHidden
    }

    /// Whether the description is shown on the canvas. Call `layout(zoom:)` afterwards.
    var showsDescription = false {
        didSet {
            if showsDescription != oldValue { needsLayout = true }
        }
    }

    /// Whether the description layer is drawing text, for tests.
    var isShowingDescription: Bool {
        !descriptionText.isHidden
    }

    /// The fill the box is drawn with, for tests. Nil for an unfilled region.
    var fillColor: CGColor? {
        box.backgroundColor
    }

    /// The box's corner radius in view points, for tests.
    var cornerRadius: CGFloat {
        box.cornerRadius
    }

    /// The frame the region is drawn at, for tests.
    var drawnFrame: Frame {
        frame
    }

    /// Whether the region's clip hides all of it, for tests.
    var isClippedAway: Bool {
        box.isHidden
    }

    /// Clips the region to `clip`, a drawn frame, or nothing when nil. A clip that leaves nothing hides the region.
    /// Call `layout(zoom:)` afterwards.
    func setClip(_ clip: Frame?) {
        guard clip != self.clip else { return }
        self.clip = clip
        needsLayout = true
    }

    /// Shows a bar for each axis the region scrolls along. Call `layout(zoom:)` afterwards.
    func setScrollIndicators(_ indicators: [ScrollLayout.Indicator]) {
        guard indicators != self.indicators else { return }
        self.indicators = indicators
        needsLayout = true
        while indicatorLayers.count < indicators.count {
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.cornerRadius = Self.scrollIndicatorThickness / 2
            layer.backgroundColor = colors?.scrollIndicator
            box.addSublayer(layer)
            indicatorLayers.append(layer)
        }
        while indicatorLayers.count > indicators.count {
            indicatorLayers.removeLast().removeFromSuperlayer()
        }
    }

    /// The scroll indicators being drawn, for tests.
    var scrollIndicatorCount: Int {
        indicatorLayers.count
    }

    /// Draws the region at `frame`, its own or one a gesture previews. Call `layout(zoom:)` afterwards.
    func setFrame(_ frame: Frame, bounds: Frame) {
        let parts = bounds.contains(frame) ? [] : frame.parts(outside: bounds)
        guard frame != self.frame || parts != self.parts else { return }
        self.frame = frame
        self.parts = parts
        needsLayout = true
        while tints.count < parts.count {
            let tint = CALayer()
            tint.anchorPoint = .zero
            tint.backgroundColor = colors?.outside
            box.insertSublayer(tint, below: textClip)
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
        applyFamily()
        title.contentsScale = scale
        descriptionText.contentsScale = scale
        linkIndicator.backgroundColor = colors.link
        for tint in tints {
            tint.backgroundColor = colors.outside
        }
        for layer in indicatorLayers {
            layer.backgroundColor = colors.scrollIndicator
        }
    }

    /// Colors the box and its text in the kind's family: a `text` region gets no fill, only the border.
    private func applyFamily() {
        guard let colors else { return }
        let family = colors.family(of: kind)
        box.backgroundColor = kind.isUnfilled ? nil : family.fill
        applyBorder()
        title.foregroundColor = family.title
        descriptionText.foregroundColor = family.description
    }

    private func applyBorder() {
        box.borderColor = isSelected ? colors?.accent : colors.map { $0.family(of: kind).border }
        box.borderWidth = isSelected ? 2 : 1
    }

    /// Lays the layers out for `zoom` when something changed since the last layout, the zoom is different, or the
    /// text was left unfitted.
    func layoutIfNeeded(zoom: Double) {
        if needsLayout || laidOutZoom != zoom || !textFitted {
            layout(zoom: zoom)
        }
    }

    /// Lays the layers out for `zoom` when something changed since the last layout or the zoom is different. Without
    /// `fitsText`, as when a zoom run rebases or ends, text already showing keeps its size, clipped, and text left
    /// unfitted at this zoom stays so.
    func layoutIfNeeded(zoom: Double, fitsText: Bool) {
        if fitsText {
            layoutIfNeeded(zoom: zoom)
        } else if needsLayout || laidOutZoom != zoom {
            layout(zoom: zoom, fitsText: false)
        }
    }

    /// Draws the title and description now if their layout marked them for display, rather than in the next commit,
    /// so the caller can count the drawing against a time budget.
    func displayTextIfNeeded() {
        title.displayIfNeeded()
        descriptionText.displayIfNeeded()
    }

    /// Whether the title and description were last sized for the zoom they are drawn at, for tests.
    var isTextFitted: Bool {
        textFitted
    }

    /// Sizes the layers for `zoom`. A title that fits keeps its natural width, so zooming redraws only the titles
    /// whose truncation changes. With `fitsText` false, as while the zoom is changing, text already showing keeps
    /// its size and is clipped to the box, so nothing redraws; a later layout with `fitsText` fits it again.
    func layout(zoom: Double, fitsText: Bool = true) {
        needsLayout = false
        laidOutZoom = zoom
        textFitted = true
        box.frame = Self.zoomed(frame, zoom)
        let radius = PaperShapes.regionCornerRadius(width: Double(frame.w), height: Double(frame.h)) * zoom
        box.cornerRadius = radius
        for (tint, part) in zip(tints, parts) {
            tint.frame = Self.zoomed(part.offsetBy(dx: -frame.x, dy: -frame.y), zoom)
            Self.roundCorners(of: tint, sharedWith: box.bounds, radius: radius)
        }
        layoutClip(zoom: zoom)
        layoutScrollIndicators()
        let inset = Self.titleInset
        let available = box.bounds.width - 2 * inset.width
        layoutLinkIndicator()
        guard available >= 8, box.bounds.height >= Self.titleHeight + 2 * inset.height else {
            textClip.isHidden = true
            title.isHidden = true
            descriptionText.isHidden = true
            return
        }
        textClip.isHidden = false
        textClip.frame = CGRect(
            x: inset.width, y: inset.height, width: floor(available), height: box.bounds.height - 2 * inset.height)
        // The title stops short of the link indicator.
        let indicatorSpace =
            linkIndicator.isHidden
            ? 0 : Self.linkIndicatorSize + Self.linkIndicatorInset + Self.linkIndicatorGap - inset.width
        let titleWidth = max(min(ceil(titleWidth), floor(available - indicatorSpace)), 0)
        if fitsText || title.isHidden {
            title.frame = CGRect(x: 0, y: 0, width: titleWidth, height: Self.titleHeight)
        } else if title.frame.width != titleWidth {
            textFitted = false
        }
        title.isHidden = false
        layoutDescription(width: floor(available), fitsText: fitsText)
    }

    /// Rounds the corners of a tint that sit on the box's own rounded corners, so the tint stays inside the box.
    private static func roundCorners(of tint: CALayer, sharedWith bounds: CGRect, radius: CGFloat) {
        let frame = tint.frame
        var corners: CACornerMask = []
        let atLeft = frame.minX <= bounds.minX
        let atRight = frame.maxX >= bounds.maxX
        let atTop = frame.minY <= bounds.minY
        let atBottom = frame.maxY >= bounds.maxY
        if atLeft && atTop { corners.insert(.layerMinXMinYCorner) }
        if atRight && atTop { corners.insert(.layerMaxXMinYCorner) }
        if atLeft && atBottom { corners.insert(.layerMinXMaxYCorner) }
        if atRight && atBottom { corners.insert(.layerMaxXMaxYCorner) }
        tint.cornerRadius = corners.isEmpty ? 0 : radius
        tint.maskedCorners = corners
    }

    /// Masks the box to the part of it inside its clip, or hides it when nothing is inside.
    private func layoutClip(zoom: Double) {
        guard let clip else {
            box.mask = nil
            box.isHidden = false
            return
        }
        guard let visible = frame.intersection(clip) else {
            box.mask = nil
            box.isHidden = true
            return
        }
        box.isHidden = false
        if visible == frame {
            box.mask = nil
            return
        }
        clipMask.frame = Self.zoomed(visible.offsetBy(dx: -frame.x, dy: -frame.y), zoom)
        box.mask = clipMask
    }

    /// Puts each scroll indicator along the right or bottom edge, where the frame sits in the content.
    private func layoutScrollIndicators() {
        let thickness = Self.scrollIndicatorThickness
        let inset = Self.scrollIndicatorInset
        let bounds = box.bounds
        for (indicator, layer) in zip(indicators, indicatorLayers) {
            switch indicator.axis {
            case .vertical:
                let track = max(bounds.height - 2 * inset, 0)
                layer.frame = CGRect(
                    x: bounds.width - inset - thickness, y: inset + track * indicator.start, width: thickness,
                    height: track * indicator.length)
            case .horizontal:
                let track = max(bounds.width - 2 * inset, 0)
                layer.frame = CGRect(
                    x: inset + track * indicator.start, y: bounds.height - inset - thickness,
                    width: track * indicator.length, height: thickness)
            }
            layer.isHidden = bounds.width < 2 * inset + thickness || bounds.height < 2 * inset + thickness
        }
    }

    /// Puts the link indicator inset from the top-right corner when the region has links and is big enough to
    /// hold it. In a short region the inset shrinks so the dot stays centered on the region's height.
    private func layoutLinkIndicator() {
        let size = Self.linkIndicatorSize
        let minimumInset: CGFloat = 2
        guard hasLinks, box.bounds.width >= size + 2 * minimumInset, box.bounds.height >= size + 2 * minimumInset
        else {
            linkIndicator.isHidden = true
            return
        }
        let inset = min(Self.linkIndicatorInset, (box.bounds.height - size) / 2)
        linkIndicator.isHidden = false
        linkIndicator.frame = CGRect(x: box.bounds.width - inset - size, y: inset, width: size, height: size)
    }

    /// Puts the description under the title, wrapped to the region's width and clipped to its height. Without
    /// `fitsText`, a description already showing keeps its size.
    private func layoutDescription(width: CGFloat, fitsText: Bool) {
        let top = Self.titleHeight
        let height = floor(textClip.bounds.height - top)
        let lineHeight = ceil(Self.descriptionFont.ascender - Self.descriptionFont.descender)
        guard showsDescription, hasDescription, height >= lineHeight else {
            descriptionText.isHidden = true
            return
        }
        let frame = CGRect(x: 0, y: top, width: width, height: height)
        if fitsText || descriptionText.isHidden {
            descriptionText.frame = frame
        } else if descriptionText.frame != frame {
            textFitted = false
        }
        descriptionText.isHidden = false
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
