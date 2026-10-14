import Foundation

/// The parenting rule (spec Section 5): after a create, move, or resize, a region's parent is the smallest region on
/// the screen whose content area fully contains it. On equal size, the one drawn on top wins. If nothing contains
/// it, it is a top-level region.
///
/// Scrolling regions are compared where the canvas draws them, at their scroll positions (`ScrollLayout`): a gesture
/// gives a drawn frame, and the region's frame in the file is that frame moved by its new parent's offsets. A
/// scrolling region takes a region only where the region overlaps its frame as drawn, so content hidden below or
/// beside the frame receives regions once it is scrolled into view (spec Section 5). With no offsets, drawn frames
/// are the file's frames.
public enum Parenting {
    /// Where a region belongs: its parent, and its frame in the file.
    public struct Placement: Equatable, Sendable {
        public var parent: RegionID?
        public var frame: Frame
    }

    /// The parent a region with `frame` should have, with nothing scrolled. `excluding` is the region being placed:
    /// it and its descendants are never candidates. Size is compared by frame area.
    public static func parent(for frame: Frame, excluding: RegionID?, in screen: Screen) -> RegionID? {
        placement(forDrawn: frame, excluding: excluding, layout: ScrollLayout(screen: screen)).parent
    }

    /// Where a region drawn at `drawn` belongs on `screen` scrolled to `offsets`.
    public static func placement(
        forDrawn drawn: Frame, excluding: RegionID?, in screen: Screen, offsets: [RegionID: ScrollOffset] = [:]
    ) -> Placement {
        placement(forDrawn: drawn, excluding: excluding, layout: ScrollLayout(screen: screen, offsets: offsets))
    }

    /// `keeping` is a scrolling region that stays a candidate even where the frame doesn't overlap it: the parent of a
    /// region that was hidden before it moved, so a nudge doesn't take it out of content it can't be seen in.
    static func placement(
        forDrawn drawn: Frame, excluding: RegionID?, layout: ScrollLayout, keeping: RegionID? = nil
    ) -> Placement {
        let index = layout.index
        let regions = index.regions
        // The excluded region's subtree is one run of draw order, skipped as a whole.
        var skipped = regions.endIndex..<regions.endIndex
        if let excluding, let position = index.position(of: excluding) {
            skipped = position..<(index[position: position].subtreeEnd + 1)
        }
        let kept = keeping.flatMap(index.position(of:))
        var best: (position: Int, area: Int)?
        // In draw order, so `<=` lets an equal-size region drawn later, on top, win the tie.
        func consider(_ position: Int) {
            let entry = layout.entry(at: position)
            guard entry.drawnContent.contains(drawn) else { return }
            if position != kept, regions[position].scroll != nil {
                guard entry.drawn.intersects(drawn) else { return }
            }
            if let current = best, current.area < entry.area { return }
            best = (position, entry.area)
        }
        // A frame with a negative size can be held by a content area away from its origin, so it checks them all.
        if drawn.w >= 0, drawn.h >= 0, let grid = layout.placementGrid() {
            grid.forEachCandidate(atX: drawn.x, y: drawn.y) { position in
                if !skipped.contains(position) { consider(position) }
            }
        } else {
            for position in regions.startIndex..<skipped.lowerBound { consider(position) }
            for position in skipped.upperBound..<regions.endIndex { consider(position) }
        }
        let parent = best.map { regions[$0.position].id }
        return Placement(parent: parent, frame: layout.fileFrame(forDrawn: drawn, inParent: parent))
    }

    /// Applies the rule to the region `id` after it changed, then to each of its former children that no longer
    /// fits in its content area. A region that changes parent becomes the last (topmost) child of its new parent.
    /// `keepingParent` keeps a scrolling parent a candidate for `id` itself (see `placement`).
    public static func reparentAfterChange(
        of id: RegionID, in screen: Screen, offsets: [RegionID: ScrollOffset] = [:], keepingParent: Bool = false
    ) {
        var changes = LayoutChanges()
        place([id], in: screen, offsets: offsets, keepingParents: keepingParent ? [id] : [], recording: &changes)
    }

    /// Applies the rule to each of `ids` in turn, as `reparentAfterChange` does to one, against one layout of the
    /// screen that is rebuilt only after a placement changed the tree. `keepingParents` are the regions whose
    /// scrolling parents stay candidates. What it is about to change goes in `changes` first.
    static func place(
        _ ids: [RegionID], in screen: Screen, offsets: [RegionID: ScrollOffset], keepingParents: Set<RegionID> = [],
        recording changes: inout LayoutChanges
    ) {
        var placer = Placer(screen: screen, offsets: offsets, recording: changes)
        changes = LayoutChanges()  // so the placer's copy is the only one and records without copying
        for id in ids {
            placer.placeAfterChange(id, keepingParent: keepingParents.contains(id))
        }
        changes = placer.changes
    }

    /// Applies the rule to each child of `region` that its content area no longer holds.
    static func replaceChildrenOutsideContent(
        of region: Region, in screen: Screen, offsets: [RegionID: ScrollOffset], recording changes: inout LayoutChanges
    ) {
        var placer = Placer(screen: screen, offsets: offsets, recording: changes)
        changes = LayoutChanges()  // so the placer's copy is the only one and records without copying
        placer.replaceChildrenOutsideContent(of: region)
        changes = placer.changes
    }

    /// Places regions one after another against one `ScrollLayout`. A placement that keeps a region's parent keeps
    /// its frame too (its frame in the file is its drawn frame plus its parent's content shift), so the layout stays
    /// valid and is rebuilt only after a placement moved a region to a new parent. Everything it changes is recorded
    /// in `changes` first.
    struct Placer {
        let screen: Screen
        let offsets: [RegionID: ScrollOffset]
        private(set) var changes: LayoutChanges
        /// Nil when the tree changed since it was built.
        private var cached: ScrollLayout?

        init(screen: Screen, offsets: [RegionID: ScrollOffset], recording changes: LayoutChanges = LayoutChanges()) {
            self.screen = screen
            self.offsets = offsets
            self.changes = changes
        }

        private mutating func layout() -> ScrollLayout {
            if let cached { return cached }
            let layout = ScrollLayout(screen: screen, offsets: offsets)
            cached = layout
            return layout
        }

        /// Places `id`, then each of its children that no longer fits its content area.
        mutating func placeAfterChange(_ id: RegionID, keepingParent: Bool = false) {
            guard let region = layout().index.region(id) else { return }
            place(id, keepingParent: keepingParent)
            replaceChildrenOutsideContent(of: region)
        }

        mutating func replaceChildrenOutsideContent(of region: Region) {
            let area = region.contentArea
            for child in region.children where !area.contains(child.frame) {
                place(child.id)
            }
        }

        /// Appends `region` as the last top-level region, keeping the layout current.
        mutating func attachTopLevel(_ region: Region) {
            changes.recordSiblings(of: nil, in: screen)
            screen.regions.append(region)
            cached?.appendTopLevel(region)
        }

        /// Moves `id` under the parent the rule picks for where it is drawn, if that differs from its current
        /// parent, and moves its subtree so it stays where it is drawn.
        mutating func place(_ id: RegionID, keepingParent: Bool = false) {
            let layout = layout()
            let index = layout.index
            guard let position = index.position(of: id) else { return }
            let entry = index[position: position]
            let placement = Parenting.placement(
                forDrawn: layout.drawnFrame(at: position), excluding: id, layout: layout,
                keeping: keepingParent ? entry.parent : nil)
            let dx = placement.frame.x - entry.region.frame.x
            let dy = placement.frame.y - entry.region.frame.y
            if dx != 0 || dy != 0 {
                for region in index.regions[position...entry.subtreeEnd] {
                    changes.recordFrame(of: region)
                    region.frame = region.frame.offsetBy(dx: dx, dy: dy)
                }
                cached = nil
            }
            guard placement.parent != entry.parent else { return }
            detach(id, in: screen, index: index, recording: &changes)
            attach(
                entry.region, toParent: placement.parent.flatMap(index.region), in: screen, recording: &changes)
            cached = nil
        }
    }

    /// Removes `id` from its sibling list.
    static func detach(_ id: RegionID, in screen: Screen, index: RegionIndex, recording changes: inout LayoutChanges) {
        guard let region = index.region(id) else { return }
        changes.recordSiblings(of: index.parent(of: id), in: screen)
        if let parent = index.parent(of: id) {
            parent.children.removeAll { $0 === region }
        } else {
            screen.regions.removeAll { $0 === region }
        }
    }

    /// Appends `region` as the last child of `parent`, or as the last top-level region.
    static func attach(
        _ region: Region, toParent parent: Region?, in screen: Screen, recording changes: inout LayoutChanges
    ) {
        changes.recordSiblings(of: parent, in: screen)
        if let parent {
            parent.children.append(region)
        } else {
            screen.regions.append(region)
        }
    }
}
