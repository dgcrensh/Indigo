import Foundation

/// The sibling lists and frames a region command changed on one screen, as they were before it changed them. Each is
/// recorded once, before its first change, so restoring them puts back exactly what the command touched, with the
/// same `Region` objects, and undo keeps region identity for the canvas. Region commands that change the tree return
/// a `RestoreLayout` of the changes as their inverse, so undo costs what the edit changed rather than the screen.
struct LayoutChanges {
    /// The screen's top-level regions, when they changed.
    private var topLevel: [Region]?
    /// Keyed by the parent region's object.
    private var children: [ObjectIdentifier: (parent: Region, children: [Region])] = [:]
    private var frames: [ObjectIdentifier: (region: Region, frame: Frame)] = [:]

    init() {}

    /// Every sibling list and frame on `screen`, for changes that build up over time where the commands that make
    /// them aren't kept, such as a region open in the details panel.
    init(wholeScreen screen: Screen) {
        recordSiblings(of: nil, in: screen)
        for region in screen.allRegions {
            recordSiblings(of: region, in: screen)
            recordFrame(of: region)
        }
    }

    /// Records the children of `parent`, or the screen's top-level regions when it is nil, unless they were recorded
    /// already. Call before changing them.
    mutating func recordSiblings(of parent: Region?, in screen: Screen) {
        guard let parent else {
            if topLevel == nil {
                topLevel = screen.regions
            }
            return
        }
        let key = ObjectIdentifier(parent)
        if children[key] == nil {
            children[key] = (parent, parent.children)
        }
    }

    /// Records the frame of `region`, unless it was recorded already. Call before changing it.
    mutating func recordFrame(of region: Region) {
        let key = ObjectIdentifier(region)
        if frames[key] == nil {
            frames[key] = (region, region.frame)
        }
    }

    /// The same lists and frames as they are on `screen` now.
    func current(in screen: Screen) -> LayoutChanges {
        var current = LayoutChanges()
        current.topLevel = topLevel.map { _ in screen.regions }
        current.children = children.mapValues { ($0.parent, $0.parent.children) }
        current.frames = frames.mapValues { ($0.region, $0.region.frame) }
        return current
    }

    func restore(into screen: Screen) {
        if let topLevel {
            screen.regions = topLevel
        }
        for entry in children.values {
            entry.parent.children = entry.children
        }
        for entry in frames.values {
            entry.region.frame = entry.frame
        }
    }
}

struct RestoreLayout: Command {
    let actionName: String
    let screen: ScreenID
    let changes: LayoutChanges

    func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let current = changes.current(in: screen)
        changes.restore(into: screen)
        return RestoreLayout(actionName: actionName, screen: self.screen, changes: current)
    }
}

/// The project's screen list, variant groups, and the links of some regions. Screen commands that add, remove or
/// reorder screens return a `RestoreStructure` of this from before they ran.
struct ProjectStructure {
    var screens: [Screen]
    var variantGroups: [VariantGroup]
    var links: [(region: Region, links: [Link])]

    init(project: Project, linksOf regions: [Region] = []) {
        screens = project.screens
        variantGroups = project.variantGroups
        links = regions.map { ($0, $0.links) }
    }

    func restore(into project: Project) {
        project.screens = screens
        project.variantGroups = variantGroups
        for entry in links {
            entry.region.links = entry.links
        }
    }
}

struct RestoreStructure: Command {
    let actionName: String
    let structure: ProjectStructure

    func apply(to project: Project) throws -> Command {
        let current = ProjectStructure(project: project, linksOf: structure.links.map(\.region))
        structure.restore(into: project)
        return RestoreStructure(actionName: actionName, structure: current)
    }
}

/// Sets one property of a region and returns the command that sets it back.
struct SetRegionValue<Value>: Command {
    let actionName: String
    let region: RegionID
    let keyPath: ReferenceWritableKeyPath<Region, Value>
    let value: Value

    func apply(to project: Project) throws -> Command {
        let target = try project.requireRegion(region)
        let old = target[keyPath: keyPath]
        target[keyPath: keyPath] = value
        return SetRegionValue(actionName: actionName, region: region, keyPath: keyPath, value: old)
    }
}

/// Sets one property of a screen and returns the command that sets it back.
struct SetScreenValue<Value>: Command {
    let actionName: String
    let screen: ScreenID
    let keyPath: ReferenceWritableKeyPath<Screen, Value>
    let value: Value

    func apply(to project: Project) throws -> Command {
        let target = try project.requireScreen(screen)
        let old = target[keyPath: keyPath]
        target[keyPath: keyPath] = value
        return SetScreenValue(actionName: actionName, screen: screen, keyPath: keyPath, value: old)
    }
}

extension Region {
    /// A deep copy with new IDs throughout. Links are kept as they are.
    func copyWithNewIDs() -> Region {
        Region(
            title: title,
            kind: kind,
            frame: frame,
            description: description,
            scroll: scroll,
            links: links,
            children: children.map { $0.copyWithNewIDs() }
        )
    }
}
