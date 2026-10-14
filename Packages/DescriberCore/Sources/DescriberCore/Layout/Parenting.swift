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
        var best: (region: Region, area: Int)?
        for region in index.regions {
            if let excluding, index.isDescendant(region.id, of: excluding) { continue }
            guard let content = layout.drawnContentArea(of: region.id), content.contains(drawn) else { continue }
            if region.scroll != nil, region.id != keeping {
                guard let frame = layout.drawnFrame(of: region.id), frame.intersects(drawn) else { continue }
            }
            // Later in the walk draws on top, so `<=` lets an equal-size later region win the tie.
            if let current = best, current.area < region.frame.area { continue }
            best = (region, region.frame.area)
        }
        let parent = best?.region.id
        return Placement(parent: parent, frame: layout.fileFrame(forDrawn: drawn, inParent: parent))
    }

    /// Applies the rule to the region `id` after it changed, then to each of its former children that no longer
    /// fits in its content area. A region that changes parent becomes the last (topmost) child of its new parent.
    /// `keepingParent` keeps a scrolling parent a candidate for `id` itself (see `placement`).
    public static func reparentAfterChange(
        of id: RegionID, in screen: Screen, offsets: [RegionID: ScrollOffset] = [:], keepingParent: Bool = false
    ) {
        place(id, in: screen, offsets: offsets, keepingParent: keepingParent)
        guard let region = RegionIndex(screen: screen).region(id) else { return }
        replaceChildrenOutsideContent(of: region, in: screen, offsets: offsets)
    }

    /// Applies the rule to each child of `region` that its content area no longer holds.
    static func replaceChildrenOutsideContent(
        of region: Region, in screen: Screen, offsets: [RegionID: ScrollOffset]
    ) {
        let area = region.contentArea
        for child in region.children where !area.contains(child.frame) {
            place(child.id, in: screen, offsets: offsets)
        }
    }

    /// Moves `id` under the parent the rule picks for where it is drawn, if that differs from its current parent,
    /// and moves its subtree so it stays where it is drawn.
    static func place(
        _ id: RegionID, in screen: Screen, offsets: [RegionID: ScrollOffset] = [:], keepingParent: Bool = false
    ) {
        let layout = ScrollLayout(screen: screen, offsets: offsets)
        let index = layout.index
        guard let entry = index[id], let drawn = layout.drawnFrame(of: id) else { return }
        let placement = placement(
            forDrawn: drawn, excluding: id, layout: layout, keeping: keepingParent ? entry.parent : nil)
        let dx = placement.frame.x - entry.region.frame.x
        let dy = placement.frame.y - entry.region.frame.y
        if dx != 0 || dy != 0 {
            for region in entry.region.subtree {
                region.frame = region.frame.offsetBy(dx: dx, dy: dy)
            }
        }
        guard placement.parent != entry.parent else { return }
        detach(id, in: screen, index: index)
        attach(entry.region, toParent: placement.parent, in: screen)
    }

    /// Removes `id` from its sibling list.
    static func detach(_ id: RegionID, in screen: Screen, index: RegionIndex) {
        if let parent = index.parent(of: id) {
            parent.children.removeAll { $0.id == id }
        } else {
            screen.regions.removeAll { $0.id == id }
        }
    }

    /// Appends `region` as the last child of `parent`, or as the last top-level region.
    static func attach(_ region: Region, toParent parent: RegionID?, in screen: Screen) {
        if let parent, let parentRegion = RegionIndex(screen: screen).region(parent) {
            parentRegion.children.append(region)
        } else {
            screen.regions.append(region)
        }
    }
}
