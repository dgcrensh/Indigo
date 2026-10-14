import Foundation

/// The fields of a region the details panel edits (spec 6.2).
public struct RegionFields: Hashable, Sendable {
    public var title: String
    public var description: String
    public var kind: RegionKind
    public var links: [Link]
    public var scroll: Scroll?

    public init(
        title: String = "", description: String = "", kind: RegionKind = .open, links: [Link] = [],
        scroll: Scroll? = nil
    ) {
        self.title = title
        self.description = description
        self.kind = kind
        self.links = links
        self.scroll = scroll
    }

    public init(_ region: Region) {
        self.init(
            title: region.title, description: region.description, kind: region.kind, links: region.links,
            scroll: region.scroll)
    }
}

/// One region open in the details panel (spec Section 6). Each change applies to the project at once, so the canvas
/// shows it while it is typed, but none is recorded until `commit()`, which records the whole session as one undo
/// step and applies the blank-title rules (roadmap D2). `cancel()` puts everything back.
public final class RegionEditor {
    public enum Outcome: Equatable, Sendable {
        /// One undo step was recorded with this name.
        case recorded(actionName: String)
        /// Nothing changed, so nothing was recorded.
        case unchanged
        /// The new region was removed because its title was blank, or the region is gone.
        case discarded
    }

    public let session: EditSession
    public let screen: ScreenID
    public let region: RegionID
    /// Whether the region was drawn for this session, so a blank title discards it.
    public let isNew: Bool
    /// The fields when the session started.
    public let original: RegionFields
    /// The fields as they are now.
    public private(set) var fields: RegionFields
    /// For a new region, the command that removes it again.
    private let removeNewRegion: Command?
    private var isFinished = false

    /// Opens an existing region.
    public init(region id: RegionID, in session: EditSession) throws {
        guard let found = session.project.region(withID: id) else { throw EditError.regionNotFound(id) }
        self.session = session
        self.screen = found.screen.id
        self.region = id
        self.isNew = false
        self.original = RegionFields(found.region)
        self.fields = original
        self.removeNewRegion = nil
    }

    /// Draws a new region with `command`, without recording it, and opens it.
    public init(creating command: CreateRegion, in session: EditSession) throws {
        let inverse = try session.applyWithoutRecording(command)
        let created = try session.project.requireRegion(command.id)
        self.session = session
        self.screen = command.screen
        self.region = command.id
        self.isNew = true
        self.original = RegionFields(created)
        self.fields = original
        self.removeNewRegion = inverse
    }

    /// Whether the region is still in the project. An undo that runs while the panel is open can remove it.
    public var regionExists: Bool {
        session.project.region(withID: region) != nil
    }

    // MARK: Changing fields

    public func setTitle(_ title: String) throws {
        try set(\.title, title, RegionCommands.setTitle(title, of: region))
    }

    public func setDescription(_ description: String) throws {
        try set(\.description, description, RegionCommands.setDescription(description, of: region))
    }

    public func setKind(_ kind: RegionKind) throws {
        try set(\.kind, kind, RegionCommands.setKind(kind, of: region))
    }

    public func setLinks(_ links: [Link]) throws {
        try set(\.links, links, RegionCommands.setLinks(links, of: region))
    }

    public func setScroll(_ scroll: Scroll?) throws {
        try set(\.scroll, scroll, RegionCommands.setScroll(scroll, of: region))
    }

    private func set<Value: Equatable>(
        _ keyPath: WritableKeyPath<RegionFields, Value>, _ value: Value, _ command: Command
    ) throws {
        guard fields[keyPath: keyPath] != value else { return }
        _ = try session.applyWithoutRecording(command)
        fields[keyPath: keyPath] = value
    }

    // MARK: Ending

    /// Ends the session and records it as one undo step. A new region with a blank title is removed instead; an
    /// existing region's blank title reverts to the one it had. The title is trimmed of surrounding white space.
    @discardableResult
    public func commit() -> Outcome {
        guard !isFinished else { return .unchanged }
        isFinished = true
        guard regionExists else { return .discarded }

        let title = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            if let removeNewRegion {
                _ = try? session.applyWithoutRecording(removeNewRegion)
                return .discarded
            }
            try? setTitle(original.title)
        } else if title != fields.title {
            try? setTitle(title)
        }

        if let removeNewRegion {
            // Undoing removes the region object, and redoing puts the same object back with its fields.
            session.record(removeNewRegion)
            return .recorded(actionName: removeNewRegion.actionName)
        }
        let restores = restoringCommands()
        guard !restores.isEmpty else { return .unchanged }
        let actionName = restores.count == 1 ? restores[0].actionName : "Edit Region"
        session.record(CompositeCommand(actionName: actionName, commands: restores))
        return .recorded(actionName: actionName)
    }

    /// Ends the session, putting back everything it changed, and records nothing.
    public func cancel() {
        guard !isFinished else { return }
        isFinished = true
        guard regionExists else { return }
        if let removeNewRegion {
            _ = try? session.applyWithoutRecording(removeNewRegion)
            return
        }
        for command in restoringCommands() {
            _ = try? session.applyWithoutRecording(command)
        }
        fields = original
    }

    /// Commands that set each changed field back to its original value.
    private func restoringCommands() -> [Command] {
        var commands: [Command] = []
        if fields.title != original.title {
            commands.append(RegionCommands.setTitle(original.title, of: region))
        }
        if fields.description != original.description {
            commands.append(RegionCommands.setDescription(original.description, of: region))
        }
        if fields.kind != original.kind {
            commands.append(RegionCommands.setKind(original.kind, of: region))
        }
        if fields.links != original.links {
            commands.append(RegionCommands.setLinks(original.links, of: region))
        }
        if fields.scroll != original.scroll {
            commands.append(RegionCommands.setScroll(original.scroll, of: region))
        }
        return commands
    }

    // MARK: Helpers

    /// The screen a newly added link points at: the first screen other than the region's own, or its own when the
    /// project has only one.
    public func newLinkTarget(in project: Project) -> ScreenID {
        project.screens.first { $0.id != screen }?.id ?? screen
    }
}

extension RegionKind {
    /// The name the details panel's Kind menu shows, such as "Menu Item".
    public var displayName: String {
        switch self {
        case .open: "Open"
        case .container: "Container"
        case .text: "Text"
        case .image: "Image"
        case .button: "Button"
        case .input: "Input"
        case .toggle: "Toggle"
        case .picker: "Picker"
        case .list: "List"
        case .navigation: "Navigation"
        case .menuItem: "Menu Item"
        }
    }
}

extension ScrollAxis {
    /// The name the details panel's Axis menu shows.
    public var displayName: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .both: "Both"
        }
    }
}

extension Scroll {
    /// What turning Scrolling on in the details panel sets: vertical, with content as wide as `frame` and twice as
    /// tall.
    public static func defaultFor(_ frame: Frame) -> Scroll {
        Scroll(axis: .vertical, contentWidth: frame.w, contentHeight: frame.h * 2)
    }

    /// These settings with the content at least as large as `frame`, since the content area starts at the frame's
    /// origin and holds everything the frame shows.
    public func clamped(to frame: Frame) -> Scroll {
        Scroll(axis: axis, contentWidth: max(contentWidth, frame.w), contentHeight: max(contentHeight, frame.h))
    }
}
