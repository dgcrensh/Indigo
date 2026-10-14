import Foundation

/// The parenting rule (spec Section 5): after a create, move, or resize, a region's parent is the smallest region on
/// the screen whose content area fully contains it. On equal size, the one drawn on top wins. If nothing contains
/// it, it is a top-level region.
public enum Parenting {
    /// The parent a region with `frame` should have. `excluding` is the region being placed: it and its
    /// descendants are never candidates. Size is compared by frame area.
    public static func parent(for frame: Frame, excluding: RegionID?, in screen: Screen) -> RegionID? {
        let index = RegionIndex(screen: screen)
        var best: (region: Region, area: Int)?
        for region in index.regions {
            if let excluding, index.isDescendant(region.id, of: excluding) { continue }
            guard region.contentArea.contains(frame) else { continue }
            // Later in the walk draws on top, so `<=` lets an equal-size later region win the tie.
            if let current = best, current.area < region.frame.area { continue }
            best = (region, region.frame.area)
        }
        return best?.region.id
    }

    /// Applies the rule to the region `id` after it changed, then to each of its former children that no longer
    /// fits in its content area. A region that changes parent becomes the last (topmost) child of its new parent.
    public static func reparentAfterChange(of id: RegionID, in screen: Screen) {
        place(id, in: screen)
        guard let region = RegionIndex(screen: screen).region(id) else { return }
        let area = region.contentArea
        for child in region.children where !area.contains(child.frame) {
            place(child.id, in: screen)
        }
    }

    /// Moves `id` under the parent the rule picks, if that differs from its current parent.
    static func place(_ id: RegionID, in screen: Screen) {
        let index = RegionIndex(screen: screen)
        guard let entry = index[id] else { return }
        let newParent = parent(for: entry.region.frame, excluding: id, in: screen)
        guard newParent != entry.parent else { return }
        detach(id, in: screen, index: index)
        attach(entry.region, toParent: newParent, in: screen)
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
