import AppKit

/// The strip across the top of the canvas shown while `settings.json` can't be used (spec 12): the error, a note that
/// the previous settings are still in use, an Open Settings button, and a close button that hides it until the error
/// changes. It goes away when the file reads again. A Paper card that keeps an orange warning border.
final class SettingsBanner: PaperSurfaceView {
    static let note = "Your previous settings are still in use."

    let messageLabel = NSTextField(wrappingLabelWithString: "")
    let openButton = NSButton(title: "Open Settings", target: nil, action: nil)
    let closeButton = NSButton(title: "", target: nil, action: nil)
    /// The error from reading the settings, or nil when there is none, whether or not the close button hid it.
    private(set) var message: String?
    /// The error the close button hid, which stays hidden until another one replaces it.
    private var dismissedMessage: String?

    init() {
        super.init(color: { $0.card }, cornerRadius: 12, hasShadow: true)
        // The system orange of each appearance, matching the warning icon.
        borderColor = { $0 == .dark ? PaperColor(hex: 0xFF9F0A) : PaperColor(hex: 0xFF9500) }

        messageLabel.font = PaperFont.rounded(ofSize: 12)
        messageLabel.textColor = .paper { $0.ink }
        messageLabel.maximumNumberOfLines = 4
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.setAccessibilityIdentifier("settingsBannerMessage")

        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.action = #selector(AppDelegate.openSettings(_:))
        openButton.setContentHuggingPriority(.required, for: .horizontal)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.target = self
        closeButton.action = #selector(dismiss(_:))
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        let icon = NSImageView(
            image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                ?? NSImage())
        icon.contentTintColor = .systemOrange
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, messageLabel, openButton, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows `message`, the error from reading the settings, or hides the banner for nil. A message the close button
    /// hid stays hidden.
    func show(message newMessage: String?) {
        if newMessage != dismissedMessage {
            dismissedMessage = nil
        }
        message = newMessage
        messageLabel.stringValue = newMessage.map { "\($0) \(Self.note)" } ?? ""
        isHidden = newMessage == nil || newMessage == dismissedMessage
    }

    @objc func dismiss(_ sender: Any?) {
        dismissedMessage = message
        isHidden = true
    }
}
