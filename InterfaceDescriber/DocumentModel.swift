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
    }
}
