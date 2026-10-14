import Foundation

/// Applies commands to a project and keeps the undo and redo stacks. The app bridges this to `NSUndoManager` in
/// `Document.perform(_:)`; the core never imports AppKit.
public final class EditSession {
    public let project: Project
    private var undoStack: [Command] = []
    private var redoStack: [Command] = []

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
        let inverse = try command.apply(to: project)
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    /// Applies `command` without recording an undo step, and returns the command that reverses it. For changes
    /// that build up one step over time, such as a region open in the details panel; `record(_:)` adds the step when
    /// they are done.
    public func applyWithoutRecording(_ command: Command) throws -> Command {
        try command.apply(to: project)
    }

    /// Records one undo step for changes already applied, given the command that reverses them. Clears redo.
    public func record(_ inverse: Command) {
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    /// Reverses the last step. Does nothing when there is nothing to undo.
    public func undo() throws {
        guard let inverse = undoStack.last else { return }
        let redo = try inverse.apply(to: project)
        undoStack.removeLast()
        redoStack.append(redo)
    }

    /// Repeats the last undone step. Does nothing when there is nothing to redo.
    public func redo() throws {
        guard let command = redoStack.last else { return }
        let inverse = try command.apply(to: project)
        redoStack.removeLast()
        undoStack.append(inverse)
    }
}
