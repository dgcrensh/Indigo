import Foundation

/// Adds a new, empty screen. A position inside a variant group puts it after the group.
public struct AddScreen: Command {
    public let actionName = "New Screen"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    /// The screen to add. Created with the command so the caller knows its ID.
    public let screen: Screen
    /// Position in the sidebar, or nil for the end.
    public let index: Int?

    public init(name: String, kind: ScreenKind = .screen, viewport: Viewport, at index: Int? = nil) {
        self.screen = Screen(name: name, kind: kind, viewport: viewport)
        self.index = index
    }

    public func apply(to project: Project) throws -> Command {
        guard project.screen(withID: screen.id) == nil else { throw EditError.nothingToDo }
        let index = self.index ?? project.screens.count
        guard (0...project.screens.count).contains(index) else { throw EditError.indexOutOfRange(index) }
        let before = ProjectStructure(project: project)
        project.screens.insert(screen, at: index)
        project.groupVariantScreens()
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Duplicates a screen just after the original (after its variant group, when it has one), with new IDs throughout.
/// Links inside the copy keep pointing at their original targets. The copy is not added to a variant group.
public struct DuplicateScreen: Command {
    public let actionName = "Duplicate Screen"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let source: ScreenID
    /// The copy's ID, chosen when the command is created.
    public let newID: ScreenID
    public let name: String?

    /// `name` defaults to the original's name followed by "Copy".
    public init(_ source: ScreenID, name: String? = nil, newID: ScreenID = .make()) {
        self.source = source
        self.name = name
        self.newID = newID
    }

    public func apply(to project: Project) throws -> Command {
        let original = try project.requireScreen(source)
        guard project.screen(withID: newID) == nil else { throw EditError.nothingToDo }
        let before = ProjectStructure(project: project)
        let copy = ScreenCommands.copy(original, id: newID, name: name ?? "\(original.name) Copy")
        project.screens.insert(copy, at: project.screens.firstIndex { $0 === original }! + 1)
        project.groupVariantScreens()
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Moves a screen to a new position in the sidebar.
public struct ReorderScreen: Command {
    public let actionName = "Move Screen"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID
    /// The screen's position after the move.
    public let index: Int

    public init(_ screen: ScreenID, to index: Int) {
        self.screen = screen
        self.index = index
    }

    public func apply(to project: Project) throws -> Command {
        let target = try project.requireScreen(screen)
        guard project.screens.indices.contains(index) else { throw EditError.indexOutOfRange(index) }
        let before = ProjectStructure(project: project)
        project.screens.removeAll { $0 === target }
        project.screens.insert(target, at: index)
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Deletes a screen, removes every link to it from other screens, and drops it from its variant group (removing
/// the group if it ends up empty). Undo restores all three. The only screen can't be deleted, since a project has
/// one or more (spec Section 2).
public struct DeleteScreen: Command {
    public let actionName = "Delete Screen"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID

    public init(_ screen: ScreenID) {
        self.screen = screen
    }

    public func apply(to project: Project) throws -> Command {
        let target = try project.requireScreen(screen)
        guard project.screens.count > 1 else { throw EditError.nothingToDo }
        let linking = ScreenCommands.incomingLinks(to: screen, in: project).compactMap {
            project.region(withID: $0.region)?.region
        }
        let before = ProjectStructure(project: project, linksOf: linking)
        for region in linking {
            region.links.removeAll { $0.screen == screen }
        }
        project.screens.removeAll { $0 === target }
        project.variantGroups = ScreenCommands.removing([screen], from: project.variantGroups)
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Duplicates a screen into the same variant group with a new viewport, creating the group if the screen has none.
/// The copy is placed after the group's last screen in the sidebar.
public struct NewVariant: Command {
    public let actionName = "New Variant"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let source: ScreenID
    public let viewport: Viewport
    public let newID: ScreenID
    public let name: String?

    /// `name` defaults to the original's name followed by the viewport preset or size in parentheses.
    public init(of source: ScreenID, viewport: Viewport, name: String? = nil, newID: ScreenID = .make()) {
        self.source = source
        self.viewport = viewport
        self.name = name
        self.newID = newID
    }

    public func apply(to project: Project) throws -> Command {
        let original = try project.requireScreen(source)
        guard project.screen(withID: newID) == nil else { throw EditError.nothingToDo }
        let before = ProjectStructure(project: project)

        let label = viewport.preset ?? "\(viewport.width) × \(viewport.height)"
        let copy = ScreenCommands.copy(original, id: newID, name: name ?? "\(original.name) (\(label))")
        copy.viewport = viewport
        // The copy goes right after the group's last screen in the sidebar, so variants stay together.
        let group = project.variantGroups.firstIndex { $0.screens.contains(source) }
        let members = group.map { project.variantGroups[$0].screens } ?? [source]
        let last = project.screens.lastIndex { members.contains($0.id) }!
        project.screens.insert(copy, at: last + 1)
        if let group {
            project.variantGroups[group].screens.append(newID)
        } else {
            project.variantGroups.append(VariantGroup(name: original.name, screens: [source, newID]))
        }
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Groups screens as variants of one another. Screens already in another group leave it first. The group's screens
/// are moved together in the sidebar, at the place of the first.
public struct GroupVariants: Command {
    public let actionName = "Group Variants"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screens: [ScreenID]
    public let name: String

    public init(_ screens: [ScreenID], name: String) {
        self.screens = screens
        self.name = name
    }

    public func apply(to project: Project) throws -> Command {
        for id in screens {
            _ = try project.requireScreen(id)
        }
        var unique: [ScreenID] = []
        for id in screens where !unique.contains(id) {
            unique.append(id)
        }
        guard unique.count >= 2 else { throw EditError.nothingToDo }
        let before = ProjectStructure(project: project)
        project.variantGroups = ScreenCommands.removing(unique, from: project.variantGroups)
        project.variantGroups.append(VariantGroup(name: name, screens: unique))
        project.groupVariantScreens()
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Dissolves the variant group a screen belongs to. The screens themselves are untouched.
public struct UngroupVariants: Command {
    public let actionName = "Ungroup Variants"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID

    public init(containing screen: ScreenID) {
        self.screen = screen
    }

    public func apply(to project: Project) throws -> Command {
        guard let group = project.variantGroups.firstIndex(where: { $0.screens.contains(screen) }) else {
            throw EditError.nothingToDo
        }
        let before = ProjectStructure(project: project)
        project.variantGroups.remove(at: group)
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Puts the screens in a new sidebar order, as a drag in the sidebar does. Variant groups are kept together.
public struct ReorderScreens: Command {
    public let actionName = "Move Screen"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    /// Every screen in the project, in the new order.
    public let order: [ScreenID]

    public init(_ order: [ScreenID]) {
        self.order = order
    }

    public func apply(to project: Project) throws -> Command {
        let current = project.screens.map(\.id)
        guard order.count == current.count, Set(order) == Set(current) else { throw EditError.nothingToDo }
        let grouped = SidebarOutline.grouping(order, groups: project.variantGroups)
        guard grouped != current else { throw EditError.nothingToDo }
        let before = ProjectStructure(project: project)
        let byID = Dictionary(uniqueKeysWithValues: project.screens.map { ($0.id, $0) })
        project.screens = grouped.map { byID[$0]! }
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Makes a screen a variant of another: it joins the other screen's group, or the two form a new group named after
/// the other screen. The screen leaves any group it was in (a group left with one screen is dissolved) and moves to
/// the end of its new group in the sidebar.
public struct JoinVariants: Command {
    public let actionName = "Make Variant"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID
    public let target: ScreenID

    public init(_ screen: ScreenID, joining target: ScreenID) {
        self.screen = screen
        self.target = target
    }

    public func apply(to project: Project) throws -> Command {
        let moving = try project.requireScreen(screen)
        let other = try project.requireScreen(target)
        guard screen != target else { throw EditError.nothingToDo }
        let targetGroup = project.variantGroups.firstIndex { $0.screens.contains(target) }
        if let targetGroup, project.variantGroups[targetGroup].screens.contains(screen) {
            throw EditError.nothingToDo
        }
        let before = ProjectStructure(project: project)
        var groups = project.variantGroups
        let groupName = targetGroup.map { groups[$0].name } ?? other.name
        groups = ScreenCommands.removing([screen], from: groups, keepingSingles: false)
        if let index = groups.firstIndex(where: { $0.screens.contains(target) }) {
            groups[index].screens.append(screen)
        } else {
            groups.append(VariantGroup(name: groupName, screens: [target, screen]))
        }
        project.variantGroups = groups
        // Next to the group's last other screen, so the group gathers around it.
        let members = groups.first { $0.screens.contains(screen) }!.screens
        project.screens.removeAll { $0 === moving }
        let last = project.screens.lastIndex { members.contains($0.id) }!
        project.screens.insert(moving, at: last + 1)
        project.groupVariantScreens()
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Takes a screen out of its variant group and puts it just after the group in the sidebar. A group left with one
/// screen is dissolved.
public struct LeaveVariantGroup: Command {
    public let actionName = "Remove from Variant Group"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID

    public init(_ screen: ScreenID) {
        self.screen = screen
    }

    public func apply(to project: Project) throws -> Command {
        let leaving = try project.requireScreen(screen)
        guard let group = project.variantGroups.first(where: { $0.screens.contains(screen) }) else {
            throw EditError.nothingToDo
        }
        let before = ProjectStructure(project: project)
        project.variantGroups = ScreenCommands.removing([screen], from: project.variantGroups, keepingSingles: false)
        project.screens.removeAll { $0 === leaving }
        let last = project.screens.lastIndex { group.screens.contains($0.id) }!
        project.screens.insert(leaving, at: last + 1)
        project.groupVariantScreens()
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Renames the variant group a screen is in.
public struct RenameVariantGroup: Command {
    public let actionName = "Rename Variant Group"
    /// Changes the screen list or variant groups, which every screen file can depend on.
    public var affectedScreens: AffectedScreens { .all }
    public let screen: ScreenID
    public let name: String

    public init(containing screen: ScreenID, to name: String) {
        self.screen = screen
        self.name = name
    }

    public func apply(to project: Project) throws -> Command {
        guard let index = project.variantGroups.firstIndex(where: { $0.screens.contains(screen) }),
            project.variantGroups[index].name != name
        else { throw EditError.nothingToDo }
        let before = ProjectStructure(project: project)
        project.variantGroups[index].name = name
        return RestoreStructure(actionName: actionName, structure: before)
    }
}

/// Commands that set one field of a screen, and queries the screen UI needs.
public enum ScreenCommands {
    public static func rename(_ screen: ScreenID, to name: String) -> Command {
        // Other screens' files name the screen in their links, and slugs depend on every name.
        SetScreenValue(actionName: "Rename Screen", screen: screen, keyPath: \.name, value: name, affectedScreens: .all)
    }

    public static func setKind(_ kind: ScreenKind, of screen: ScreenID) -> Command {
        SetScreenValue(actionName: "Change Screen Kind", screen: screen, keyPath: \.kind, value: kind)
    }

    /// Changes the frame drawn on the canvas and the saved value. Regions are untouched (spec 8.2).
    public static func setViewport(_ viewport: Viewport, of screen: ScreenID) -> Command {
        SetScreenValue(actionName: "Change Viewport", screen: screen, keyPath: \.viewport, value: viewport)
    }

    public static func setScroll(_ scroll: Scroll?, of screen: ScreenID) -> Command {
        SetScreenValue(actionName: "Change Scrolling", screen: screen, keyPath: \.scroll, value: scroll)
    }

    /// Regions on other screens that link to `screen`, which would lose those links if it were deleted. Used for
    /// the delete confirmation (milestone 8).
    public static func incomingLinks(to screen: ScreenID, in project: Project) -> [(screen: ScreenID, region: RegionID)]
    {
        project.screens.filter { $0.id != screen }.flatMap { source in
            source.allRegions.filter { $0.links.contains { $0.screen == screen } }.map { (source.id, $0.id) }
        }
    }

    static func copy(_ screen: Screen, id: ScreenID, name: String) -> Screen {
        Screen(
            id: id,
            name: name,
            kind: screen.kind,
            viewport: screen.viewport,
            scroll: screen.scroll,
            regions: screen.regions.map { $0.copyWithNewIDs() }
        )
    }

    /// `groups` with `screens` taken out, dropping groups left empty, and groups left with one screen too unless
    /// `keepingSingles`.
    static func removing(
        _ screens: [ScreenID], from groups: [VariantGroup], keepingSingles: Bool = true
    ) -> [VariantGroup] {
        groups.compactMap { group in
            var group = group
            let count = group.screens.count
            group.screens.removeAll { screens.contains($0) }
            if group.screens.isEmpty || (!keepingSingles && group.screens.count == 1 && count > 1) {
                return nil
            }
            return group
        }
    }
}
