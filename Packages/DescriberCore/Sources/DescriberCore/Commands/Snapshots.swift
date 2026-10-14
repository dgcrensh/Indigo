import Foundation

/// The shape of one screen's region tree: which region is where, and every region's frame. Restoring it puts the
/// same `Region` objects back, so undo keeps region identity for the canvas. Region commands that change the tree
/// return a `RestoreLayout` of the layout from before they ran as their inverse.
struct RegionLayout {
    var topLevel: [RegionID]
    var children: [RegionID: [RegionID]]
    var frames: [RegionID: Frame]
    /// Every region object the layout refers to.
    var regions: [RegionID: Region]

    init(screen: Screen) {
        topLevel = screen.regions.map(\.id)
        children = [:]
        frames = [:]
        regions = [:]
        for region in screen.allRegions {
            children[region.id] = region.children.map(\.id)
            frames[region.id] = region.frame
            regions[region.id] = region
        }
    }

    func restore(into screen: Screen) {
        for (id, region) in regions {
            region.frame = frames[id]!
            region.children = children[id]!.map { regions[$0]! }
        }
        screen.regions = topLevel.map { regions[$0]! }
    }
}

struct RestoreLayout: Command {
    let actionName: String
    let screen: ScreenID
    let layout: RegionLayout

    func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let current = RegionLayout(screen: screen)
        layout.restore(into: screen)
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: current)
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
