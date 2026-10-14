import Foundation

/// One undoable edit. Every change to a project goes through a command (CLAUDE.md), so undo, redo, and tests see
/// every change.
public protocol Command {
    /// The name the Undo and Redo menu items show, such as "Move Region". An inverse has the same name.
    var actionName: String { get }

    /// Applies the edit and returns the command that undoes it. A command that throws leaves the project unchanged.
    func apply(to project: Project) throws -> Command
}

/// Why a command could not be applied.
public enum EditError: Error, Equatable {
    case screenNotFound(ScreenID)
    case regionNotFound(RegionID)
    /// A create or paste would add a region whose ID is already on the screen.
    case regionAlreadyExists(RegionID)
    /// A create or resize asked for a frame smaller than `Geometry.minimumSize` in either dimension.
    case belowMinimumSize(Frame)
    /// A reorder asked for a position outside the list.
    case indexOutOfRange(Int)
    /// The command would change nothing it is meant to change, such as grouping fewer than two screens.
    case nothingToDo
}

/// Several commands applied as one undo step. If one throws, the ones already applied are undone first.
public struct CompositeCommand: Command {
    public let actionName: String
    public let commands: [Command]

    public init(actionName: String, commands: [Command]) {
        self.actionName = actionName
        self.commands = commands
    }

    public func apply(to project: Project) throws -> Command {
        var inverses: [Command] = []
        do {
            for command in commands {
                inverses.append(try command.apply(to: project))
            }
        } catch {
            for inverse in inverses.reversed() {
                _ = try? inverse.apply(to: project)
            }
            throw error
        }
        return CompositeCommand(actionName: actionName, commands: inverses.reversed())
    }
}

extension Project {
    func requireScreen(_ id: ScreenID) throws -> Screen {
        guard let screen = screen(withID: id) else { throw EditError.screenNotFound(id) }
        return screen
    }

    /// The region with `id` on any screen, and the screen it is on.
    public func region(withID id: RegionID) -> (region: Region, screen: Screen)? {
        for screen in screens {
            if let region = RegionIndex(screen: screen).region(id) {
                return (region, screen)
            }
        }
        return nil
    }

    func requireRegion(_ id: RegionID) throws -> Region {
        guard let found = region(withID: id) else { throw EditError.regionNotFound(id) }
        return found.region
    }
}
