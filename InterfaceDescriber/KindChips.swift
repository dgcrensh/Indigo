import AppKit
import DescriberCore

/// The details card's kind picker: a wrapping row of chips, one per kind in `RegionKind.allCases` order, each in its
/// family's fill and text color, the chosen one ringed with the accent. It is one Tab stop: Left and Right move
/// between chips and Space chooses one, and those keys never reach the canvas.
final class KindChips: NSView {
    static let chipHeight: CGFloat = 24
    static let chipPadding: CGFloat = 10
    static let spacing: CGFloat = 6
    static let font = PaperFont.rounded(ofSize: 12, weight: .medium)
    /// The width the chips wrap to before the view has one of its own: the details card's form.
    static let defaultWidth: CGFloat = 244

    /// The kind the open region has. Setting it doesn't call `onChoose`.
    var selectedKind: RegionKind = .open {
        didSet {
            if selectedKind != oldValue { needsDisplay = true }
        }
    }
    /// The chip Space would choose while the row has focus.
    private(set) var focusedKind: RegionKind = .open
    /// Called with a kind chosen by click or by Space.
    var onChoose: ((RegionKind) -> Void)?
    private var laidOutWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .default
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Kind")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    // MARK: Layout

    /// Each chip's frame when the row is `width` wide, wrapping onto new rows.
    func chipFrames(width: CGFloat) -> [(kind: RegionKind, frame: CGRect)] {
        var frames: [(kind: RegionKind, frame: CGRect)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        for kind in RegionKind.allCases {
            let textWidth = (kind.displayName as NSString).size(withAttributes: [.font: Self.font]).width
            let chipWidth = ceil(textWidth) + 2 * Self.chipPadding
            if x > 0, x + chipWidth > width {
                x = 0
                y += Self.chipHeight + Self.spacing
            }
            frames.append((kind: kind, frame: CGRect(x: x, y: y, width: chipWidth, height: Self.chipHeight)))
            x += chipWidth + Self.spacing
        }
        return frames
    }

    /// The frame of `kind`'s chip as the row is laid out now, for clicks and tests.
    func chipFrame(for kind: RegionKind) -> CGRect? {
        chipFrames(width: currentWidth).first { $0.kind == kind }?.frame
    }

    private var currentWidth: CGFloat {
        bounds.width > 0 ? bounds.width : Self.defaultWidth
    }

    override var intrinsicContentSize: NSSize {
        let bottom = chipFrames(width: currentWidth).map(\.frame.maxY).max() ?? 0
        return NSSize(width: NSView.noIntrinsicMetric, height: bottom)
    }

    override func layout() {
        super.layout()
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let palette = PaperPalette.palette(for: effectiveAppearance)
        for (kind, frame) in chipFrames(width: currentWidth) {
            let colors = palette.colors(for: kind)
            let radius = frame.height / 2
            colors.fill.nsColor.setFill()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            if kind == selectedKind {
                let ring = NSBezierPath(
                    roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
                ring.lineWidth = 2
                palette.accent.nsColor.setStroke()
                ring.stroke()
            } else {
                let border = NSBezierPath(
                    roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
                border.lineWidth = 1
                colors.border.withAlpha(0.6).nsColor.setStroke()
                border.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: colors.text.nsColor]
            let size = (kind.displayName as NSString).size(withAttributes: attributes)
            let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            (kind.displayName as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    override var focusRingMaskBounds: NSRect {
        chipFrame(for: focusedKind) ?? bounds
    }

    override func drawFocusRingMask() {
        guard let frame = chipFrame(for: focusedKind) else { return }
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
    }

    // MARK: Focus, clicks and keys

    override func becomeFirstResponder() -> Bool {
        focusedKind = selectedKind
        noteFocusRingMaskChanged()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let kind = chipFrames(width: currentWidth).first(where: { $0.frame.contains(point) })?.kind else {
            return
        }
        window?.makeFirstResponder(self)
        focus(kind)
        choose(kind)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:  // Left
            move(by: -1)
        case 124:  // Right
            move(by: 1)
        case 125, 126:  // Down and Up do nothing here, rather than nudge a region.
            break
        case 49:  // Space
            choose(focusedKind)
        case 48:  // Tab
            if event.modifierFlags.contains(.shift) {
                window?.selectKeyView(preceding: self)
            } else {
                window?.selectKeyView(following: self)
            }
        default:
            super.keyDown(with: event)
        }
    }

    /// Moves the focus `offset` chips along, stopping at the ends.
    func move(by offset: Int) {
        let kinds = RegionKind.allCases
        let index = kinds.firstIndex(of: focusedKind) ?? 0
        focus(kinds[min(max(index + offset, 0), kinds.count - 1)])
    }

    private func focus(_ kind: RegionKind) {
        focusedKind = kind
        noteFocusRingMaskChanged()
        needsDisplay = true
    }

    /// Chooses `kind`, as a click on its chip does.
    func choose(_ kind: RegionKind) {
        selectedKind = kind
        onChoose?(kind)
    }
}
