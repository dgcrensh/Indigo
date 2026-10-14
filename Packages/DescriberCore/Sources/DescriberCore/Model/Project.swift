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
}
