import Foundation

/// Draws a new region. Unless a parent is given, the parenting rule picks its parent.
public struct CreateRegion: Command {
    public let actionName = "New Region"
    public let screen: ScreenID
    public let id: RegionID
    public let frame: Frame
    public let title: String
    public let kind: RegionKind
    /// Grid size to snap every edge to, or nil when snapping is off for this gesture.
    public let grid: Int?
    /// Places the region as the last child of this region instead of applying the parenting rule.
    public let parent: RegionID?

    public init(
        screen: ScreenID,
        frame: Frame,
        title: String = "",
        kind: RegionKind = .open,
        id: RegionID = .make(),
        grid: Int? = nil,
        parent: RegionID? = nil
    ) {
        self.screen = screen
        self.frame = frame
        self.title = title
        self.kind = kind
        self.id = id
        self.grid = grid
        self.parent = parent
    }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        let frame = grid.map { Snapping.snap(frame: self.frame, grid: $0, mode: .draw) } ?? self.frame
        guard Geometry.meetsMinimumSize(frame) else { throw EditError.belowMinimumSize(frame) }
        guard !index.contains(id) else { throw EditError.regionAlreadyExists(id) }
        if let parent, !index.contains(parent) { throw EditError.regionNotFound(parent) }

        let before = RegionLayout(screen: screen)
        let region = Region(id: id, title: title, kind: kind, frame: frame)
        Parenting.attach(region, toParent: parent, in: screen)
        if parent == nil {
            Parenting.place(id, in: screen)
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Moves one or more regions by the same delta. Descendants move with them, and each moved region is re-parented
/// by the parenting rule.
public struct MoveRegions: Command {
    public let screen: ScreenID
    public let regions: [RegionID]
    public let dx: Int
    public let dy: Int
    /// Grid size to snap to, or nil when snapping is off for this gesture. The first moved region's origin lands
    /// on the grid and the others keep their offsets from it.
    public let grid: Int?

    public init(screen: ScreenID, regions: [RegionID], dx: Int, dy: Int, grid: Int? = nil) {
        self.screen = screen
        self.regions = regions
        self.dx = dx
        self.dy = dy
        self.grid = grid
    }

    public var actionName: String { regions.count == 1 ? "Move Region" : "Move Regions" }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        let roots = try topmostRegions(regions, in: index)
        guard let first = roots.first else { throw EditError.nothingToDo }

        let delta = Self.snappedDelta(moving: first.frame, dx: dx, dy: dy, grid: grid)

        let before = RegionLayout(screen: screen)
        for root in roots {
            for region in root.subtree {
                region.frame = region.frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        for root in roots {
            Parenting.reparentAfterChange(of: root.id, in: screen)
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }

    /// The delta that moves `frame` by `dx`, `dy` and then lands its origin on the grid, or the delta itself when
    /// `grid` is nil. The canvas previews a move with this, so the preview and the result agree.
    public static func snappedDelta(moving frame: Frame, dx: Int, dy: Int, grid: Int?) -> (x: Int, y: Int) {
        guard let grid else { return (dx, dy) }
        let target = Snapping.snap(frame: frame.offsetBy(dx: dx, dy: dy), grid: grid, mode: .move)
        return (target.x - frame.x, target.y - frame.y)
    }
}

/// Resizes one region to a new frame. Children keep their frames; any that no longer fit are re-parented.
public struct ResizeRegion: Command {
    public let actionName = "Resize Region"
    public let screen: ScreenID
    public let region: RegionID
    public let frame: Frame
    /// The edges being dragged; only these snap.
    public let edges: Snapping.Edges
    /// Grid size to snap to, or nil when snapping is off for this gesture.
    public let grid: Int?

    public init(screen: ScreenID, region: RegionID, frame: Frame, edges: Snapping.Edges = .all, grid: Int? = nil) {
        self.screen = screen
        self.region = region
        self.frame = frame
        self.edges = edges
        self.grid = grid
    }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        guard let target = RegionIndex(screen: screen).region(region) else { throw EditError.regionNotFound(region) }
        let frame = grid.map { Snapping.snap(frame: self.frame, grid: $0, mode: .resize(edges)) } ?? self.frame
        guard Geometry.meetsMinimumSize(frame) else { throw EditError.belowMinimumSize(frame) }

        let before = RegionLayout(screen: screen)
        target.frame = frame
        Parenting.reparentAfterChange(of: region, in: screen)
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Deletes one or more regions and all their descendants.
public struct DeleteRegions: Command {
    public let screen: ScreenID
    public let regions: [RegionID]

    public init(screen: ScreenID, regions: [RegionID]) {
        self.screen = screen
        self.regions = regions
    }

    public var actionName: String { regions.count == 1 ? "Delete Region" : "Delete Regions" }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        let roots = try topmostRegions(regions, in: index)
        guard !roots.isEmpty else { throw EditError.nothingToDo }

        let before = RegionLayout(screen: screen)
        for root in roots {
            Parenting.detach(root.id, in: screen, index: index)
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Moves a region to the top or bottom of its siblings.
public struct ReorderRegion: Command {
    public enum Position: Sendable {
        /// Last among its siblings, drawn on top of them.
        case front
        /// First among its siblings, drawn below them.
        case back
    }

    public let screen: ScreenID
    public let region: RegionID
    public let position: Position

    public init(screen: ScreenID, region: RegionID, to position: Position) {
        self.screen = screen
        self.region = region
        self.position = position
    }

    public var actionName: String { position == .front ? "Bring to Front" : "Send to Back" }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        guard let target = index.region(region) else { throw EditError.regionNotFound(region) }

        let before = RegionLayout(screen: screen)
        func reorder(_ siblings: inout [Region]) {
            siblings.removeAll { $0.id == region }
            if position == .front {
                siblings.append(target)
            } else {
                siblings.insert(target, at: 0)
            }
        }
        if let parent = index.parent(of: region) {
            reorder(&parent.children)
        } else {
            reorder(&screen.regions)
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Pastes copies of regions, with new IDs throughout each subtree and links kept. The copies are made when the
/// command is created, so `pasted` tells the caller which regions to select.
public struct PasteRegions: Command {
    public let actionName = "Paste"
    public let screen: ScreenID
    /// The new regions, top-level copies only; their children come with them.
    public let pasted: [Region]
    /// Places the copies under this region instead of applying the parenting rule.
    public let parent: RegionID?

    /// `regions` are copied; the originals are never inserted, so they may come from any screen or the clipboard.
    public init(screen: ScreenID, regions: [Region], parent: RegionID? = nil) {
        self.screen = screen
        self.pasted = regions.map { $0.copyWithNewIDs() }
        self.parent = parent
    }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        if let existing = pasted.flatMap(\.subtree).first(where: { index.contains($0.id) }) {
            throw EditError.regionAlreadyExists(existing.id)
        }
        if let parent, !index.contains(parent) { throw EditError.regionNotFound(parent) }
        guard !pasted.isEmpty else { throw EditError.nothingToDo }

        let before = RegionLayout(screen: screen)
        for region in pasted {
            Parenting.attach(region, toParent: parent, in: screen)
            if parent == nil {
                Parenting.place(region.id, in: screen)
            }
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Commands that set one field of a region. Each returns its own inverse, and none moves the region in the tree.
public enum RegionCommands {
    public static func setTitle(_ title: String, of region: RegionID) -> Command {
        SetRegionValue(actionName: "Edit Title", region: region, keyPath: \.title, value: title)
    }

    public static func setDescription(_ description: String, of region: RegionID) -> Command {
        SetRegionValue(actionName: "Edit Description", region: region, keyPath: \.description, value: description)
    }

    public static func setKind(_ kind: RegionKind, of region: RegionID) -> Command {
        SetRegionValue(actionName: "Change Kind", region: region, keyPath: \.kind, value: kind)
    }

    public static func setLinks(_ links: [Link], of region: RegionID) -> Command {
        SetRegionValue(actionName: "Edit Links", region: region, keyPath: \.links, value: links)
    }

    public static func setScroll(_ scroll: Scroll?, of region: RegionID) -> Command {
        SetRegionValue(actionName: "Change Scrolling", region: region, keyPath: \.scroll, value: scroll)
    }
}

/// The regions among `ids` that aren't inside another region in `ids`, in the order given. Throws if any ID isn't
/// on the screen.
func topmostRegions(_ ids: [RegionID], in index: RegionIndex) throws -> [Region] {
    var seen = Set<RegionID>()
    var regions: [Region] = []
    for id in ids where seen.insert(id).inserted {
        guard let region = index.region(id) else { throw EditError.regionNotFound(id) }
        regions.append(region)
    }
    return regions.filter { region in
        !index.path(to: region.id).dropLast().contains { seen.contains($0.id) }
    }
}
