import AppKit
import DescriberCore

/// The details panel (spec Section 6): the form where a region's title, description, kind, links and scrolling are
/// edited. Every change goes straight to the open `RegionEditor` through the model, which records the whole session
/// as one undo step when the panel closes.
///
/// AppKit rather than SwiftUI, because Return, Tab, Shift-Tab and Escape have to be redirected inside text views
/// (spec 6.3), which `doCommandBy` delegate methods do reliably.
final class DetailsPanelController: NSViewController {
    static let width: CGFloat = 300

    let model: DocumentModel
    /// Asks the window to commit the open region and close the panel, for Escape.
    var onClose: (() -> Void)?

    let titleField = NSTextField(string: "")
    let descriptionView: NSTextView
    private let descriptionScrollView: NSScrollView
    let kindPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let linksStack = NSStackView()
    private(set) var linkRows: [LinkRow] = []
    let addLinkButton = NSButton(title: "Add Link", target: nil, action: nil)
    let scrollsCheckbox = NSButton(checkboxWithTitle: "Scrolls", target: nil, action: nil)
    let axisPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let contentWidthField = NSTextField(string: "")
    let contentHeightField = NSTextField(string: "")
    private let scrollOptions = NSStackView()
    /// Set while the controls are filled from the model, so their change callbacks don't write back.
    private var isLoading = false
    /// Undo for typing in the panel's text fields, kept apart from the document's so Cmd-Z while typing undoes
    /// typing, and typing never leaves steps on the document's stack. The description and the panel's field editor
    /// use it, and it is cleared whenever the panel shows another region or closes.
    let textUndoManager = UndoManager()
    /// The field editor for the panel's text fields, which the window hands out through its delegate. A fresh one
    /// is made for each region, so no editing state carries over from the last.
    private(set) var fieldEditor = PanelTextView()

    init(model: DocumentModel) {
        self.model = model
        let textView = PanelTextView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 140))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        descriptionView = textView
        descriptionScrollView = NSScrollView()
        descriptionScrollView.hasVerticalScroller = true
        descriptionScrollView.documentView = textView
        super.init(nibName: nil, bundle: nil)
        textView.panelUndoManager = textUndoManager
        fieldEditor = makeFieldEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func makeFieldEditor() -> PanelTextView {
        let editor = PanelTextView()
        editor.isFieldEditor = true
        editor.panelUndoManager = textUndoManager
        return editor
    }

    var editor: RegionEditor? {
        model.details
    }

    // MARK: Building the form

    override func loadView() {
        titleField.placeholderString = "Title"
        titleField.usesSingleLineMode = true
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.isScrollable = true
        titleField.cell?.wraps = false
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        titleField.delegate = self

        descriptionView.isRichText = false
        descriptionView.allowsUndo = true
        descriptionView.font = .systemFont(ofSize: NSFont.systemFontSize)
        descriptionView.textContainerInset = NSSize(width: 2, height: 4)
        descriptionView.delegate = self
        descriptionScrollView.borderType = .bezelBorder
        descriptionScrollView.heightAnchor.constraint(equalToConstant: 140).isActive = true

        for kind in RegionKind.allCases {
            kindPopUp.menu?.addItem(NSMenuItem(title: kind.displayName, action: nil, keyEquivalent: ""))
        }
        kindPopUp.target = self
        kindPopUp.action = #selector(kindChanged(_:))

        linksStack.orientation = .vertical
        linksStack.alignment = .leading
        linksStack.spacing = 6
        addLinkButton.target = self
        addLinkButton.action = #selector(addLink(_:))
        addLinkButton.bezelStyle = .rounded
        addLinkButton.controlSize = .small

        scrollsCheckbox.target = self
        scrollsCheckbox.action = #selector(scrollsChanged(_:))
        for axis in ScrollAxis.allCases {
            axisPopUp.menu?.addItem(NSMenuItem(title: axis.displayName, action: nil, keyEquivalent: ""))
        }
        axisPopUp.target = self
        axisPopUp.action = #selector(scrollChanged(_:))
        for field in [contentWidthField, contentHeightField] {
            field.delegate = self
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        }
        contentWidthField.placeholderString = "Width"
        contentHeightField.placeholderString = "Height"
        scrollOptions.orientation = .vertical
        scrollOptions.alignment = .leading
        scrollOptions.spacing = 6
        scrollOptions.addArrangedSubview(row(label("Axis"), axisPopUp))
        scrollOptions.addArrangedSubview(
            row(label("Content"), contentWidthField, label("×"), contentHeightField, label("pt")))

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 6
        form.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        form.translatesAutoresizingMaskIntoConstraints = false
        form.addArrangedSubview(sectionLabel("Title"))
        form.addArrangedSubview(titleField)
        form.setCustomSpacing(14, after: titleField)
        form.addArrangedSubview(sectionLabel("Description"))
        form.addArrangedSubview(descriptionScrollView)
        form.setCustomSpacing(14, after: descriptionScrollView)
        form.addArrangedSubview(sectionLabel("Kind"))
        form.addArrangedSubview(kindPopUp)
        form.setCustomSpacing(14, after: kindPopUp)
        form.addArrangedSubview(sectionLabel("Links"))
        form.addArrangedSubview(linksStack)
        form.addArrangedSubview(addLinkButton)
        form.setCustomSpacing(14, after: addLinkButton)
        form.addArrangedSubview(sectionLabel("Scrolling"))
        form.addArrangedSubview(scrollsCheckbox)
        form.addArrangedSubview(scrollOptions)
        for view in [titleField, descriptionScrollView, linksStack] {
            view.widthAnchor.constraint(equalTo: form.widthAnchor, constant: -32).isActive = true
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(form)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: document.topAnchor),
            form.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            form.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        scrollView.frame = NSRect(x: 0, y: 0, width: Self.width, height: 500)
        view = scrollView
        updateKeyViewLoop()
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func row(_ views: NSView...) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    /// Tab order, top to bottom. Pop-ups and buttons are skipped unless Full Keyboard Access is on, as everywhere.
    private func updateKeyViewLoop() {
        var views: [NSView] = [titleField, descriptionView, kindPopUp]
        for row in linkRows {
            views += [row.screenPopUp, row.triggerField, row.removeButton]
        }
        views += [addLinkButton, scrollsCheckbox, axisPopUp, contentWidthField, contentHeightField]
        let following: [NSView] = Array(views.dropFirst()) + [titleField]
        for (view, next) in zip(views, following) {
            view.nextKeyView = next
        }
    }

    // MARK: Showing a region

    /// Fills the form from the open region.
    func load() {
        _ = view
        guard let editor else { return }
        isLoading = true
        defer { isLoading = false }
        // End any editing first, so the field editor can't write the last region's text back into a field.
        if let window = view.window, isEditingText(window.firstResponder) {
            window.makeFirstResponder(nil)
        }
        titleField.abortEditing()
        fieldEditor = makeFieldEditor()
        textUndoManager.removeAllActions()
        let fields = editor.fields
        titleField.stringValue = fields.title
        descriptionView.string = fields.description
        kindPopUp.selectItem(at: RegionKind.allCases.firstIndex(of: fields.kind) ?? 0)
        rebuildLinkRows()
        loadScroll()
    }

    private func loadScroll() {
        let scroll = editor?.fields.scroll
        scrollsCheckbox.state = scroll == nil ? .off : .on
        scrollOptions.isHidden = scroll == nil
        if let scroll {
            axisPopUp.selectItem(at: ScrollAxis.allCases.firstIndex(of: scroll.axis) ?? 0)
            contentWidthField.stringValue = String(scroll.contentWidth)
            contentHeightField.stringValue = String(scroll.contentHeight)
        }
    }

    private func rebuildLinkRows() {
        for row in linkRows {
            row.removeFromSuperview()
        }
        let screens = model.project.screens
        linkRows = (editor?.fields.links ?? []).map { link in
            let row = LinkRow(screens: screens, link: link)
            row.screenPopUp.target = self
            row.screenPopUp.action = #selector(linkChanged(_:))
            row.triggerField.delegate = self
            row.removeButton.target = self
            row.removeButton.action = #selector(removeLink(_:))
            return row
        }
        for row in linkRows {
            linksStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: linksStack.widthAnchor).isActive = true
        }
        updateKeyViewLoop()
    }

    /// Whether `responder` is a text view editing one of the panel's fields.
    func isEditingText(_ responder: NSResponder?) -> Bool {
        guard let text = responder as? NSText, isViewLoaded else { return false }
        // A field editor may sit outside the field it edits, but the field is its delegate.
        if let field = (text as? NSTextView)?.delegate as? NSView, field.isDescendant(of: view) {
            return true
        }
        return text.isDescendant(of: view)
    }

    // MARK: Changes

    private func edit(_ change: (RegionEditor) throws -> Void) {
        guard !isLoading else { return }
        do {
            try model.editDetails(change)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func kindChanged(_ sender: Any?) {
        let kind = RegionKind.allCases[max(kindPopUp.indexOfSelectedItem, 0)]
        edit { try $0.setKind(kind) }
    }

    /// The links as the rows show them.
    private var linksFromRows: [Link] {
        let screens = model.project.screens
        return zip(linkRows, editor?.fields.links ?? []).map { row, link in
            let index = row.screenPopUp.indexOfSelectedItem
            let screen = screens.indices.contains(index) ? screens[index].id : link.screen
            let trigger = row.triggerField.stringValue
            return Link(screen: screen, trigger: trigger.isEmpty ? nil : trigger)
        }
    }

    @objc private func linkChanged(_ sender: Any?) {
        let links = linksFromRows
        edit { try $0.setLinks(links) }
    }

    @objc func addLink(_ sender: Any?) {
        guard let editor else { return }
        let links = linksFromRows + [Link(screen: editor.newLinkTarget(in: model.project))]
        edit { try $0.setLinks(links) }
        rebuildLinkRows()
    }

    @objc private func removeLink(_ sender: NSButton) {
        guard let index = linkRows.firstIndex(where: { $0.removeButton === sender }) else { return }
        var links = linksFromRows
        links.remove(at: index)
        edit { try $0.setLinks(links) }
        rebuildLinkRows()
    }

    /// The open region's frame, which the scroll content can't be smaller than.
    private var regionFrame: Frame? {
        editor.flatMap { model.project.region(withID: $0.region)?.region.frame }
    }

    /// The scroll positions on the open region's screen, so children that changing the scrolling re-places land where
    /// they are drawn.
    private var scrollOffsets: [RegionID: ScrollOffset] {
        editor.flatMap { model.project.editorState.screens[$0.screen]?.scrollOffsets } ?? [:]
    }

    @objc func scrollsChanged(_ sender: Any?) {
        guard let frame = regionFrame else { return }
        let scroll = scrollsCheckbox.state == .on ? Scroll.defaultFor(frame) : nil
        let offsets = scrollOffsets
        edit { try $0.setScroll(scroll, scrollOffsets: offsets) }
        loadScroll()
    }

    /// Applies the axis and content size the form shows. A size that isn't a whole number keeps the old one, and the
    /// content is never smaller than the frame.
    @objc private func scrollChanged(_ sender: Any?) {
        guard let frame = regionFrame, let current = editor?.fields.scroll else { return }
        let axis = ScrollAxis.allCases[max(axisPopUp.indexOfSelectedItem, 0)]
        let width = Int(contentWidthField.stringValue.trimmingCharacters(in: .whitespaces)) ?? current.contentWidth
        let height = Int(contentHeightField.stringValue.trimmingCharacters(in: .whitespaces)) ?? current.contentHeight
        let scroll = Scroll(axis: axis, contentWidth: width, contentHeight: height).clamped(to: frame)
        let offsets = scrollOffsets
        edit { try $0.setScroll(scroll, scrollOffsets: offsets) }
        loadScroll()
    }

    // MARK: Keys

    /// Commits and closes, applying a content size still being typed first.
    func commitAndClose() {
        if editor?.fields.scroll != nil {
            scrollChanged(nil)
        }
        onClose?()
    }

    /// Moves focus to the next or previous field, for Tab and Shift-Tab in the description, where they would
    /// otherwise insert a tab.
    private func moveFocus(from view: NSView, forward: Bool) {
        guard let window = view.window else { return }
        if forward {
            window.selectKeyView(following: view)
        } else {
            window.selectKeyView(preceding: view)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        commitAndClose()
    }

    /// Escape on a pop-up, checkbox or button, which don't turn it into `cancelOperation(_:)` themselves.
    override func keyDown(with event: NSEvent) {
        if KeyCombo(event: event) == KeyCombo("escape") {
            commitAndClose()
        } else {
            super.keyDown(with: event)
        }
    }
}

extension DetailsPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === titleField {
            let title = field.stringValue
            edit { try $0.setTitle(title) }
        } else if linkRows.contains(where: { $0.triggerField === field }) {
            linkChanged(field)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === contentWidthField || field === contentHeightField {
            scrollChanged(field)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            commitAndClose()
            return true
        case #selector(NSResponder.insertNewline(_:)) where control === titleField:
            view.window?.makeFirstResponder(descriptionView)
            return true
        default:
            return false
        }
    }
}

extension DetailsPanelController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === descriptionView else { return }
        let description = descriptionView.string
        edit { try $0.setDescription(description) }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard textView === descriptionView else { return false }
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            moveFocus(from: textView, forward: true)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            moveFocus(from: textView, forward: false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            commitAndClose()
            return true
        default:
            return false
        }
    }
}

/// One link in the details panel: the target screen, an optional trigger, and a remove button.
final class LinkRow: NSStackView {
    let screenPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let triggerField = NSTextField(string: "")
    let removeButton = NSButton(title: "−", target: nil, action: nil)

    init(screens: [Screen], link: Link) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        // Items are added one by one, since `addItems(withTitles:)` drops screens with the same name.
        for screen in screens {
            screenPopUp.menu?.addItem(NSMenuItem(title: screen.name, action: nil, keyEquivalent: ""))
        }
        if let index = screens.firstIndex(where: { $0.id == link.screen }) {
            screenPopUp.selectItem(at: index)
        } else {
            screenPopUp.menu?.addItem(NSMenuItem(title: "Missing Screen", action: nil, keyEquivalent: ""))
            screenPopUp.selectItem(at: screens.count)
        }
        screenPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        screenPopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        triggerField.placeholderString = "Trigger"
        triggerField.stringValue = link.trigger ?? ""
        triggerField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .small
        removeButton.toolTip = "Remove Link"
        addArrangedSubview(screenPopUp)
        addArrangedSubview(triggerField)
        addArrangedSubview(removeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// A text view whose typing undo goes to the details panel's own undo manager, and which answers Undo and Redo
/// itself, so they reach that manager rather than the document's while it has focus.
final class PanelTextView: NSTextView {
    weak var panelUndoManager: UndoManager?

    override var undoManager: UndoManager? {
        panelUndoManager ?? super.undoManager
    }

    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return undoManager?.canUndo ?? false
        case #selector(redo(_:)): return undoManager?.canRedo ?? false
        default: return super.validateUserInterfaceItem(item)
        }
    }
}

/// A document view whose origin is at the top-left, so a short form sits at the top of its scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
