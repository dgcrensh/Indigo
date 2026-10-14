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
    /// Whether drawing, moving and resizing snap to the grid, which the canvas then shows. Toggled with `S` from
    /// milestone 5.
    var snappingEnabled = true

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

    /// Starts over with `project`, as after reading or reverting.
    func replaceProject(with project: Project) {
        session = EditSession(project: project)
        activeScreenID = project.initialScreen
        noteChange()
    }

    /// Records that the project changed.
    func noteChange() {
        revision += 1
    }
}
