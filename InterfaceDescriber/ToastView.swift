import AppKit
import DescriberCore

/// The small label near the bottom center of the canvas, just above the tool pill, that confirms a mode change, such
/// as "Region tool — R" (spec Section 4). A card-colored capsule with ink text. It never takes clicks or focus, and
/// fades after about a second.
final class ToastView: PaperSurfaceView {
    /// How long a toast stays fully visible before it fades.
    static let visibleDuration: TimeInterval = 1
    private let label = NSTextField(labelWithString: "")
    private var fade: DispatchWorkItem?

    init() {
        super.init(color: { $0.card }, hasShadow: true)
        isCapsule = true
        label.font = PaperFont.rounded(ofSize: 13, weight: .medium)
        label.textColor = .paper { $0.ink }
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        alphaValue = 0
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The text showing, or nil once the toast has faded.
    private(set) var text: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func show(_ text: String) {
        self.text = text
        label.stringValue = text
        fade?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.text = nil
        }
    }
}
