import DescriberCore
import Foundation
import Observation

/// What a document window shows: the edit session holding the project, and the active screen. Views read it
/// through Observation, so they follow undo, redo and Revert.
@Observable
final class DocumentModel {
    /// Replaced when the document is read or reverted.
    var session: EditSession
    /// The screen the canvas shows. Window state only; saving it arrives with screen management (milestone 8).
    var activeScreenID: ScreenID?
    /// Changes after every command, undo, redo and replacement of the project, so views that draw the model (the
    /// canvas) know to draw again. Regions aren't observable themselves.
    private(set) var revision = 0
    /// Whether drawing, moving and resizing snap to the grid, which the canvas then shows. Toggled with `S`.
    var snappingEnabled = true
    /// The active tool. Every window starts with the Select tool.
    var tool: Tool = .select
    /// The selected regions on the active screen. Editor state, so changing it isn't an edit.
    var selection: [RegionID] = []
    /// The keybinds; overrides from settings arrive in milestone 10.
    var keybinds = KeybindRegistry.defaults

    init(project: Project) {
        session = EditSession(project: project)
        activeScreenID = project.initialScreen
    }

    var project: Project {
        session.project
    }

    var activeScreen: Screen? {
        activeScreenID.flatMap { project.screen(withID: $0) }
    }

    /// The region open in the details panel, or nil while the panel is closed.
    private(set) var details: RegionEditor?
    /// Called after the details panel records an undo step, with its name, so the document can register it with
    /// the undo manager.
    @ObservationIgnored var didRecordStep: ((String) -> Void)?
    /// Called after the details panel opens, switches to another region, or closes, so the window can show it.
    @ObservationIgnored var detailsDidChange: (() -> Void)?

    /// Starts over with `project`, as after reading or reverting.
    func replaceProject(with project: Project) {
        let hadDetails = details != nil
        details = nil
        session = EditSession(project: project)
        activeScreenID = project.initialScreen
        noteChange()
        if hadDetails {
            detailsDidChange?()
        }
    }

    // MARK: Details panel

    /// Opens an existing region in the details panel and selects it, committing the region open there now.
    func openDetails(for region: RegionID) throws {
        guard details?.region != region else { return }
        try openDetails { try RegionEditor(region: region, in: session) }
    }

    /// Draws a region with `command` and opens it in the details panel, committing the region open there now. The
    /// drawing is recorded with the panel session when it closes, or dropped with a blank title.
    func openDetails(creating command: CreateRegion) throws {
        try openDetails { try RegionEditor(creating: command, in: session) }
    }

    private func openDetails(_ makeEditor: () throws -> RegionEditor) throws {
        commitDetails()
        details = nil
        do {
            let editor = try makeEditor()
            details = editor
            selection = [editor.region]
        } catch {
            noteChange()
            detailsDidChange?()
            throw error
        }
        noteChange()
        detailsDidChange?()
    }

    /// Changes a field of the region open in the details panel.
    func editDetails(_ change: (RegionEditor) throws -> Void) rethrows {
        guard let details else { return }
        try change(details)
        noteChange()
    }

    /// Commits the region open in the details panel as one undo step and closes the panel.
    func closeDetails() {
        guard details != nil else { return }
        commitDetails()
        details = nil
        detailsDidChange?()
    }

    /// Puts back everything the open details session changed, records nothing, and closes the panel. Undo and redo
    /// do this first, so they never interleave with unrecorded changes.
    func cancelDetails() {
        guard let details else { return }
        details.cancel()
        self.details = nil
        noteChange()
        detailsDidChange?()
    }

    private func commitDetails() {
        guard let details else { return }
        if case .recorded(let actionName) = details.commit() {
            didRecordStep?(actionName)
        }
        noteChange()
    }

    /// Records that the project changed.
    func noteChange() {
        revision += 1
    }
}
