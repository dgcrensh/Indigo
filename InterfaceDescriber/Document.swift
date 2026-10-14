import AppKit
import DescriberCore

/// A `.uidesc` project package. Reads and writes through the core's package format and routes every edit through
/// the core's `EditSession`, bridged to `NSUndoManager`.
final class Document: NSDocument {
    /// A new document's one screen gets the default viewport from settings, with This Device measured from the main
    /// display; reading a file replaces it.
    let model = DocumentModel(
        project: .untitled(
            viewport: SettingsStore.shared.settings.newScreenViewport(
                displaySize: Document.mainDisplaySize)))

    /// The main display's size in points, the whole screen.
    private static var mainDisplaySize: (width: Double, height: Double) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return (Double(bounds.width), Double(bounds.height))
    }

    /// The package as last read or written, kept so a save only replaces files that changed and keeps files the
    /// project doesn't own.
    private var packageWrapper = FileWrapper(directoryWithFileWrappers: [:])
    /// The files in `packageWrapper`, which the core compares against to find what changed.
    private var packageTree: PackageTree = [:]

    override class var autosavesInPlace: Bool {
        true
    }

    override init() {
        super.init()
        model.didRecordStep = { [weak self] actionName in
            self?.registerUndoStep(named: actionName)
        }
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(model: model)
        controller.canvasController.performCommand = { [weak self] command in
            guard let self else { return }
            try self.perform(command)
        }
        controller.screenController.performCommand = { [weak self] command in
            guard let self else { return }
            try self.perform(command)
        }
        addWindowController(controller)
    }

    // MARK: Reading and writing

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        // The core reads project.json first and stops there if its schemaVersion isn't supported.
        let project = try ProjectPackage.read { PackageWrapper.contents(at: $0, in: fileWrapper) }
        packageWrapper = fileWrapper
        packageTree = PackageWrapper.tree(of: fileWrapper)
        model.replaceProject(with: project)
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let changes = ProjectPackage.write(project: model.project, previous: packageTree).changes
        PackageWrapper.apply(changes, to: packageWrapper)
        packageTree = ProjectPackage.applying(changes, to: packageTree)
        return packageWrapper
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        // The reverted project has a fresh edit session, so the old undo steps no longer apply.
        undoManager?.removeAllActions()
    }

    // MARK: Editing

    /// Applies `command` to the project as one undo step named after it. Every edit goes through here. A region
    /// open in the details panel is committed and closed first, so its step comes before this one.
    func perform(_ command: Command) throws {
        model.closeDetails()
        try model.session.perform(command)
        model.noteChange()
        registerUndoStep(named: command.actionName)
    }

    /// Registers the step that reverses the session's last change: an undo step normally, a redo step while
    /// undoing.
    private func registerUndoStep(named actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            document.reverseLastStep()
        }
        undoManager.setActionName(actionName)
    }

    private func reverseLastStep() {
        guard let undoManager else { return }
        // Unrecorded changes in the details panel would be out of step with the undo stack.
        model.cancelDetails()
        let session = model.session
        do {
            if undoManager.isUndoing {
                guard session.canUndo else { return }
                try session.undo()
                model.noteChange()
                registerUndoStep(named: session.redoActionName ?? "")
            } else {
                guard session.canRedo else { return }
                try session.redo()
                model.noteChange()
                registerUndoStep(named: session.undoActionName ?? "")
            }
        } catch {
            // A step that fails leaves the project unchanged but the stacks out of step with the undo manager.
            assertionFailure("Undo or redo failed: \(error)")
            undoManager.removeAllActions()
        }
    }
}
