import Foundation

/// Draws a new region. Unless a parent is given, the parenting rule picks its parent at the screen's scroll
/// positions, and `frame` is where it is drawn (see `ScrollLayout`).
public struct CreateRegion: Command {
    public let actionName = "New Region"
    public let screen: ScreenID
    public let id: RegionID
    public let frame: Frame
    public let title: String
    public let kind: RegionKind
    /// Grid size to snap every edge to, or nil when snapping is off for this gesture.
    public let grid: Int?
    /// Places the region as the last child of this region instead of applying the parenting rule. `frame` is then
    /// its frame in the file.
    public let parent: RegionID?
    /// The scroll positions of the screen's scrolling regions, from its editor state.
    public let scrollOffsets: [RegionID: ScrollOffset]

    public init(
        screen: ScreenID,
        frame: Frame,
        title: String = "",
        kind: RegionKind = .open,
        id: RegionID = .make(),
        grid: Int? = nil,
        parent: RegionID? = nil,
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) {
        self.screen = screen
        self.frame = frame
        self.title = title
        self.kind = kind
        self.id = id
        self.grid = grid
        self.parent = parent
        self.scrollOffsets = scrollOffsets
    }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let layout = ScrollLayout(screen: screen, offsets: scrollOffsets)
        let index = layout.index
        let frame = grid.map { Snapping.snap(frame: self.frame, grid: $0, mode: .draw) } ?? self.frame
        guard Geometry.meetsMinimumSize(frame) else { throw EditError.belowMinimumSize(frame) }
        guard !index.contains(id) else { throw EditError.regionAlreadyExists(id) }
        if let parent, !index.contains(parent) { throw EditError.regionNotFound(parent) }

        let before = RegionLayout(screen: screen)
        let placement =
            parent.map { Parenting.Placement(parent: $0, frame: frame) }
            ?? Parenting.placement(forDrawn: frame, excluding: nil, layout: layout)
        let region = Region(id: id, title: title, kind: kind, frame: placement.frame)
        Parenting.attach(region, toParent: placement.parent.flatMap(index.region), in: screen)
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Moves one or more regions by the same delta where they are drawn. Descendants move with them, and each moved
/// region is re-parented by the parenting rule at the screen's scroll positions, so it lands where it was dropped.
public struct MoveRegions: Command {
    public let screen: ScreenID
    public let regions: [RegionID]
    public let dx: Int
    public let dy: Int
    /// Grid size to snap to, or nil when snapping is off for this gesture. The first moved region's drawn origin
    /// lands on the grid and the others keep their offsets from it.
    public let grid: Int?
    /// The scroll positions of the screen's scrolling regions, from its editor state.
    public let scrollOffsets: [RegionID: ScrollOffset]

    public init(
        screen: ScreenID, regions: [RegionID], dx: Int, dy: Int, grid: Int? = nil,
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) {
        self.screen = screen
        self.regions = regions
        self.dx = dx
        self.dy = dy
        self.grid = grid
        self.scrollOffsets = scrollOffsets
    }

    public var actionName: String { regions.count == 1 ? "Move Region" : "Move Regions" }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let layout = ScrollLayout(screen: screen, offsets: scrollOffsets)
        let index = layout.index
        let roots = try topmostRegions(regions, in: index)
        guard let first = roots.first else { throw EditError.nothingToDo }

        let delta = Self.snappedDelta(
            moving: layout.drawnFrame(of: first.id) ?? first.frame, dx: dx, dy: dy, grid: grid)
        // A region nobody can see keeps its scrolling parent, so nudging a hidden region doesn't move it out.
        let hidden = Set(roots.filter { layout.visibleFrame(of: $0.id) == nil }.map(\.id))

        let before = RegionLayout(screen: screen)
        for root in roots {
            guard let position = index.position(of: root.id) else { continue }
            for region in index.regions[position...index[position: position].subtreeEnd] {
                region.frame = region.frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        Parenting.place(roots.map(\.id), in: screen, offsets: scrollOffsets, keepingParents: hidden)
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

/// Resizes one region to a new frame, where it is drawn. Children keep their frames; any that no longer fit are
/// re-parented.
public struct ResizeRegion: Command {
    public let actionName = "Resize Region"
    public let screen: ScreenID
    public let region: RegionID
    public let frame: Frame
    /// The edges being dragged; only these snap.
    public let edges: Snapping.Edges
    /// Grid size to snap to, or nil when snapping is off for this gesture.
    public let grid: Int?
    /// The scroll positions of the screen's scrolling regions, from its editor state.
    public let scrollOffsets: [RegionID: ScrollOffset]

    public init(
        screen: ScreenID, region: RegionID, frame: Frame, edges: Snapping.Edges = .all, grid: Int? = nil,
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) {
        self.screen = screen
        self.region = region
        self.frame = frame
        self.edges = edges
        self.grid = grid
        self.scrollOffsets = scrollOffsets
    }

    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let layout = ScrollLayout(screen: screen, offsets: scrollOffsets)
        guard let target = layout.index.region(region) else { throw EditError.regionNotFound(region) }
        let frame = grid.map { Snapping.snap(frame: self.frame, grid: $0, mode: .resize(edges)) } ?? self.frame
        guard Geometry.meetsMinimumSize(frame) else { throw EditError.belowMinimumSize(frame) }

        let before = RegionLayout(screen: screen)
        let shift = layout.contentShift(of: layout.index[region]?.parent)
        target.frame = frame.offsetBy(dx: shift.x, dy: shift.y)
        Parenting.reparentAfterChange(of: region, in: screen, offsets: scrollOffsets)
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

/// Moves several regions to the top or bottom of their own siblings, keeping their order among themselves (spec
/// Section 7). Regions with different parents are reordered within their own parents.
public struct ReorderRegions: Command {
    public let screen: ScreenID
    public let regions: [RegionID]
    public let position: ReorderRegion.Position

    public init(screen: ScreenID, regions: [RegionID], to position: ReorderRegion.Position) {
        self.screen = screen
        self.regions = regions
        self.position = position
    }

    public var actionName: String { position == .front ? "Bring to Front" : "Send to Back" }

    /// Throws `nothingToDo` when every region is already where it would go, so no empty step is recorded.
    public func apply(to project: Project) throws -> Command {
        let screen = try project.requireScreen(self.screen)
        let index = RegionIndex(screen: screen)
        if let missing = regions.first(where: { !index.contains($0) }) { throw EditError.regionNotFound(missing) }
        let selected = Set(regions)

        func reordered(_ siblings: [Region]) -> [Region] {
            let moving = siblings.filter { selected.contains($0.id) }
            let staying = siblings.filter { !selected.contains($0.id) }
            return position == .front ? staying + moving : moving + staying
        }
        let lists = [screen.regions] + screen.allRegions.map(\.children)
        guard lists.contains(where: { reordered($0).map(\.id) != $0.map(\.id) }) else {
            throw EditError.nothingToDo
        }

        let before = RegionLayout(screen: screen)
        for region in screen.allRegions where region.children.contains(where: { selected.contains($0.id) }) {
            region.children = reordered(region.children)
        }
        screen.regions = reordered(screen.regions)
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Pastes copies of regions, with new IDs throughout each subtree and links kept. The copies are made when the
/// command is created, so `pasted` tells the caller which regions to select.
public struct PasteRegions: Command {
    /// "Paste", or "Duplicate" for a duplicate.
    public let actionName: String
    public let screen: ScreenID
    /// The new regions, top-level copies only; their children come with them.
    public let pasted: [Region]
    /// Places the copies under this region instead of applying the parenting rule.
    public let parent: RegionID?
    /// The scroll positions of the screen's scrolling regions. Without `parent`, the copies' frames are where they
    /// are drawn.
    public let scrollOffsets: [RegionID: ScrollOffset]

    /// `regions` are copied; the originals are never inserted, so they may come from any screen or the clipboard.
    public init(
        screen: ScreenID, regions: [Region], parent: RegionID? = nil, actionName: String = "Paste",
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) {
        self.actionName = actionName
        self.screen = screen
        self.pasted = regions.map { $0.copyWithNewIDs() }
        self.parent = parent
        self.scrollOffsets = scrollOffsets
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
        if let parent = parent.flatMap(index.region) {
            parent.children.append(contentsOf: pasted)
        } else {
            // Each copy lands on top of the screen and is placed before the next is added, against one layout.
            var placer = Parenting.Placer(screen: screen, offsets: scrollOffsets)
            for region in pasted {
                placer.attachTopLevel(region)
                placer.place(region.id)
            }
        }
        return RestoreLayout(actionName: actionName, screen: self.screen, layout: before)
    }
}

/// Commands that set one field of a region. Each returns its own inverse, and none moves the region itself in the
/// tree.
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

    /// Children that no longer fit the new content area are re-placed by the parenting rule (see `SetRegionScroll`).
    public static func setScroll(
        _ scroll: Scroll?, of region: RegionID, scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) -> Command {
        SetRegionScroll(region: region, scroll: scroll, scrollOffsets: scrollOffsets)
    }
}

/// Sets a region's scrolling. Turning it off or shrinking the content can leave children outside the content area;
/// each of those is re-placed by the parenting rule at the screen's scroll positions. Undoes to the same layout.
public struct SetRegionScroll: Command {
    public let actionName = "Change Scrolling"
    public let region: RegionID
    public let scroll: Scroll?
    public let scrollOffsets: [RegionID: ScrollOffset]

    public init(region: RegionID, scroll: Scroll?, scrollOffsets: [RegionID: ScrollOffset] = [:]) {
        self.region = region
        self.scroll = scroll
        self.scrollOffsets = scrollOffsets
    }

    public func apply(to project: Project) throws -> Command {
        guard let (target, screen) = project.region(withID: region) else { throw EditError.regionNotFound(region) }
        let before = RegionLayout(screen: screen)
        let old = target.scroll
        target.scroll = scroll
        Parenting.replaceChildrenOutsideContent(of: target, in: screen, offsets: scrollOffsets)
        return CompositeCommand(
            actionName: actionName,
            commands: [
                RestoreLayout(actionName: actionName, screen: screen.id, layout: before),
                SetRegionValue(actionName: actionName, region: region, keyPath: \.scroll, value: old),
            ])
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
    return regions.filter { !index.isInside($0.id, anyOf: seen) }
}
