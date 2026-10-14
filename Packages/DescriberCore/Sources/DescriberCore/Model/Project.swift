import Foundation
import Observation

/// One `.uidesc` package: its screens in sidebar order, variant groups, and editor-only state.
@Observable
public final class Project {
    /// The `.uidesc` format version this build reads and writes.
    public static let schemaVersion = 1
    /// The only unit the format uses.
    public static let units = "points"

    public var name: String
    /// Screens in sidebar order.
    public var screens: [Screen]
    public var variantGroups: [VariantGroup]
    public var editorState: EditorState

    public init(
        name: String,
        screens: [Screen] = [],
        variantGroups: [VariantGroup] = [],
        editorState: EditorState = EditorState()
    ) {
        self.name = name
        self.screens = screens
        self.variantGroups = variantGroups
        self.editorState = editorState
    }

    public func screen(withID id: ScreenID) -> Screen? {
        screens.first { $0.id == id }
    }

    /// The project a new document starts with: one screen at `viewport`, the default viewport from settings.
    public static func untitled(viewport: Viewport = .defaultForNewScreens) -> Project {
        Project(name: "Untitled", screens: [Screen(name: "Screen 1", viewport: viewport)])
    }

    /// The screen a newly opened window shows: the last active screen when it still exists, otherwise the first.
    public var initialScreen: ScreenID? {
        if let last = editorState.lastActiveScreen, screen(withID: last) != nil {
            return last
        }
        return screens.first?.id
    }
}
