import AppKit
import DescriberCore

extension PaperColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension PaperAppearance {
    /// Dark for an appearance whose best match is Dark Aqua, light otherwise.
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

extension PaperPalette {
    /// The palette for an AppKit appearance.
    static func palette(for appearance: NSAppearance) -> PaperPalette {
        palette(for: PaperAppearance(appearance))
    }
}

extension NSColor {
    /// A color of the palette that follows the appearance it is drawn in, for views and text.
    static func paper(_ color: @escaping (PaperPalette) -> PaperColor) -> NSColor {
        NSColor(name: nil) { appearance in
            color(PaperPalette.palette(for: appearance)).nsColor
        }
    }
}

/// The type of the Paper look: SF Pro Rounded, the system font's rounded design.
enum PaperFont {
    static func rounded(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }
}

/// The soft shadow under cards, the tool pill and the toast.
enum PaperShadow {
    static func apply(to view: NSView, radius: CGFloat = 10, offset: CGFloat = 3) {
        let palette = PaperPalette.palette(for: view.effectiveAppearance)
        let shadow = NSShadow()
        shadow.shadowColor = palette.sheetShadow.nsColor
        shadow.shadowBlurRadius = radius
        shadow.shadowOffset = NSSize(width: 0, height: -offset)
        view.shadow = shadow
    }
}

/// A rounded surface of the Paper look, such as a card or a well, in a palette color that follows the appearance,
/// optionally with the soft shadow and a border.
class PaperSurfaceView: NSView {
    var color: (PaperPalette) -> PaperColor {
        didSet { needsDisplay = true }
    }
    var borderColor: ((PaperPalette) -> PaperColor)? {
        didSet { needsDisplay = true }
    }
    var borderWidth: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat {
        didSet { needsDisplay = true }
    }
    /// Draws the corner radius as half the height, for capsules.
    var isCapsule = false {
        didSet { needsLayout = true }
    }
    var hasShadow: Bool {
        didSet { updateShadow() }
    }

    init(
        color: @escaping (PaperPalette) -> PaperColor, cornerRadius: CGFloat = 0, hasShadow: Bool = false
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.hasShadow = hasShadow
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateShadow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let palette = PaperPalette.palette(for: effectiveAppearance)
        layer.backgroundColor = color(palette).cgColor
        layer.cornerRadius = isCapsule ? bounds.height / 2 : cornerRadius
        if let borderColor {
            layer.borderColor = borderColor(palette).cgColor
            layer.borderWidth = borderWidth
        } else {
            layer.borderWidth = 0
        }
    }

    override func layout() {
        super.layout()
        if isCapsule { needsDisplay = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateShadow()
    }

    private func updateShadow() {
        if hasShadow {
            PaperShadow.apply(to: self)
        } else {
            shadow = nil
        }
    }

    /// The color the surface is drawn in now, for tests.
    var resolvedColor: PaperColor {
        color(PaperPalette.palette(for: effectiveAppearance))
    }
}
