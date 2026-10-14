import Foundation

/// Applies commands to a project and keeps the undo and redo stacks. The app bridges this to `NSUndoManager` in
/// `Document.perform(_:)`; the core never imports AppKit.
public final class EditSession {
    public let project: Project
    private var undoStack: [Command] = []
    private var redoStack: [Command] = []
    /// Counts of applied changes, for the project and per screen, so a save can skip screens nobody touched.
    public private(set) var generations = PackageGenerations()

    public init(project: Project) {
        self.project = project
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// The name of the step Undo would reverse, such as "Move Region".
    public var undoActionName: String? { undoStack.last?.actionName }
    /// The name of the step Redo would repeat.
    public var redoActionName: String? { redoStack.last?.actionName }
    /// How many steps Undo can reverse.
    public var undoDepth: Int { undoStack.count }

    /// Applies `command` as one undo step and clears redo. If it throws, nothing changes.
    public func perform(_ command: Command) throws {
        let inverse = try apply(command)
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    /// Applies `command` without recording an undo step, and returns the command that reverses it. For changes
    /// that build up one step over time, such as a region open in the details panel; `record(_:)` adds the step when
    /// they are done.
    public func applyWithoutRecording(_ command: Command) throws -> Command {
        try apply(command)
    }

    /// Records one undo step for changes already applied, given the command that reverses them. Clears redo.
    public func record(_ inverse: Command) {
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    /// Reverses the last step. Does nothing when there is nothing to undo.
    public func undo() throws {
        guard let inverse = undoStack.last else { return }
        let redo = try apply(inverse)
        undoStack.removeLast()
        redoStack.append(redo)
    }

    /// Repeats the last undone step. Does nothing when there is nothing to redo.
    public func redo() throws {
        guard let command = redoStack.last else { return }
        let inverse = try apply(command)
        redoStack.removeLast()
        undoStack.append(inverse)
    }

    /// Applies `command` and counts the change against the screens its inverse names: a command that finds its
    /// region by ID learns the screen only when applied. A command that throws counts nothing.
    private func apply(_ command: Command) throws -> Command {
        let inverse = try command.apply(to: project)
        generations.count(inverse.affectedScreens)
        return inverse
    }
}

/// How many changes an edit session has applied: to the project, to every screen at once, and to each screen. A
/// screen's file can only have changed since a write when its own count or the every-screen count has. Counts from
/// different sessions never match, since each session has its own `session` ID.
public struct PackageGenerations: Equatable, Sendable {
    /// Identifies the session the counts come from.
    public let session = UUID()
    /// Every applied change.
    public private(set) var project = 0
    /// The last change that could touch every screen's file, as a project count.
    public private(set) var allScreens = 0
    /// The last change to each screen, as a project count. Absent for screens no change named.
    public private(set) var screens: [ScreenID: Int] = [:]

    public init() {}

    /// Counts one applied change to `affected`.
    public mutating func count(_ affected: AffectedScreens) {
        project += 1
        switch affected {
        case .all:
            allScreens = project
        case .screens(let ids):
            for id in ids {
                screens[id] = project
            }
        }
    }

    /// What a write records for `screen`'s file; when it is the same at the next write, the file hasn't changed.
    public func stamp(for screen: ScreenID) -> ScreenStamp {
        ScreenStamp(session: session, screen: screen, own: screens[screen] ?? 0, allScreens: allScreens)
    }
}

/// One screen's counts at a write. See `PackageGenerations.stamp(for:)`.
public struct ScreenStamp: Equatable, Sendable {
    let session: UUID
    let screen: ScreenID
    let own: Int
    let allScreens: Int
}
