import AppKit
import DescriberCore

/// The floating pill at the bottom center of the canvas: Select, Region and Write, then the snap button with the grid
/// size. Clicking a button does what its key does. The pill never takes key focus, so keybinds keep working after a
/// click, and clicks on it never reach the canvas.
final class ToolPill: PaperSurfaceView {
    let toolButtons: [Tool: PillButton]
    let snapButton = PillButton(title: "Snap")
    /// Called with the tool a button picks.
    var onChooseTool: ((Tool) -> Void)?
    /// Called for a click on the snap button: true when Option was held, which opens the grid size.
    var onSnap: ((_ optionHeld: Bool) -> Void)?
    private(set) var tool: Tool = .select

    init() {
        var buttons: [Tool: PillButton] = [:]
        for tool in Tool.allCases {
            buttons[tool] = PillButton(title: Self.title(of: tool))
        }
        toolButtons = buttons
        super.init(color: { $0.card }, hasShadow: true)
        isCapsule = true
        let divider = PaperSurfaceView(color: { $0.sheetBorder })
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 18),
        ])
        let views: [NSView] = Tool.allCases.compactMap { buttons[$0] } + [divider, snapButton]
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        stack.setCustomSpacing(8, after: buttons[.write] ?? snapButton)
        stack.setCustomSpacing(8, after: divider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (tool, button) in buttons {
            button.target = self
            button.action = #selector(toolClicked(_:))
            button.setAccessibilityIdentifier("toolPill.\(tool.rawValue)")
        }
        snapButton.target = self
        snapButton.action = #selector(snapClicked(_:))
        snapButton.setAccessibilityIdentifier("toolPill.snap")
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Tools")
        update(tool: .select, snapping: true, gridSize: Snapping.defaultGridSize, keybinds: .defaults)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private static func title(of tool: Tool) -> String {
        switch tool {
        case .select: "Select"
        case .region: "Region"
        case .write: "Write"
        }
    }

    /// Shows the active tool, whether snapping is on and the grid size, with tooltips naming the current keys.
    func update(tool: Tool, snapping: Bool, gridSize: Int, keybinds: KeybindRegistry) {
        self.tool = tool
        for (buttonTool, button) in toolButtons {
            button.style = buttonTool == tool ? .active : .plain
            button.toolTip = ToolPillTooltip.text(for: buttonTool, keybinds: keybinds)
        }
        snapButton.title = "Snap \(gridSize)"
        snapButton.style = snapping ? .tinted : .plain
        snapButton.toolTip = ToolPillTooltip.snapping(keybinds: keybinds)
    }

    @objc private func toolClicked(_ sender: PillButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        onChooseTool?(tool)
    }

    @objc private func snapClicked(_ sender: Any?) {
        pressSnap(optionHeld: NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }

    /// A click on the snap button, with or without Option. Tests call this directly.
    func pressSnap(optionHeld: Bool) {
        onSnap?(optionHeld)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A press on the pill between its buttons does nothing, rather than passing on.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// A button of the tool pill: a rounded capsule with text, plain, tinted with the accent, or filled with it. It
/// never takes focus.
final class PillButton: NSButton {
    enum Style {
        case plain
        /// Accent text on a faint accent wash, for a mode that is on.
        case tinted
        /// On-accent text on the accent, for the active tool.
        case active
    }

    var style: Style = .plain {
        didSet {
            if style != oldValue { needsDisplay = true }
        }
    }

    override var title: String {
        didSet { invalidateIntrinsicContentSize() }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        refusesFirstResponder = true
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    static let font = PaperFont.rounded(ofSize: 12, weight: .semibold)

    override var acceptsFirstResponder: Bool { false }
    override var wantsUpdateLayer: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: Self.font]).width
        return NSSize(width: ceil(width) + 24, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let palette = PaperPalette.palette(for: effectiveAppearance)
        let background: PaperColor?
        let text: PaperColor
        switch style {
        case .plain:
            background = isHighlighted ? palette.well : nil
            text = palette.ink
        case .tinted:
            background = palette.accent.withAlpha(isHighlighted ? 0.2 : 0.12)
            text = palette.accent
        case .active:
            background = palette.accent
            text = palette.onAccent
        }
        if let background {
            background.nsColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: text.nsColor]
        let size = (title as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (title as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// Whether the button is filled with the accent, as the active tool's is, for tests.
    var isAccentFilled: Bool {
        style == .active
    }
}
