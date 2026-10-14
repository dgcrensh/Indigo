import Foundation

@testable import DescriberCore

/// The parenting rule and the four commands that re-place regions, exactly as `main` ran them before milestone 17:
/// every placement builds a new `ScrollLayout` and `RegionIndex` of the whole screen, and descendants are found by
/// walking the path to the root. Slow, but simple enough to trust, so `ParentingEquivalenceTests` checks the commands
/// against it. Kept for good as the guard on the parenting rule (milestone 17, open questions). These apply edits
/// without recording undo.
enum ReferenceCommands {
    // MARK: Commands

    static func apply(_ command: MoveRegions, to project: Project) throws {
        let screen = try project.requireScreen(command.screen)
        let index = RegionIndex(screen: screen)
        let roots = try topmostRegions(command.regions, in: index)
        guard let first = roots.first else { throw EditError.nothingToDo }

        let layout = ScrollLayout(screen: screen, offsets: command.scrollOffsets)
        let delta = MoveRegions.snappedDelta(
            moving: layout.drawnFrame(of: first.id) ?? first.frame, dx: command.dx, dy: command.dy,
            grid: command.grid)
        let hidden = Set(roots.filter { layout.visibleFrame(of: $0.id) == nil }.map(\.id))

        for root in roots {
            for region in root.subtree {
                region.frame = region.frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        for root in roots {
            reparentAfterChange(
                of: root.id, in: screen, offsets: command.scrollOffsets, keepingParent: hidden.contains(root.id))
        }
    }

    static func apply(_ command: ResizeRegion, to project: Project) throws {
        let screen = try project.requireScreen(command.screen)
        let layout = ScrollLayout(screen: screen, offsets: command.scrollOffsets)
        guard let target = layout.index.region(command.region) else {
            throw EditError.regionNotFound(command.region)
        }
        let frame =
            command.grid.map { Snapping.snap(frame: command.frame, grid: $0, mode: .resize(command.edges)) }
            ?? command.frame
        guard Geometry.meetsMinimumSize(frame) else { throw EditError.belowMinimumSize(frame) }

        let shift = layout.contentShift(of: layout.index[command.region]?.parent)
        target.frame = frame.offsetBy(dx: shift.x, dy: shift.y)
        reparentAfterChange(of: command.region, in: screen, offsets: command.scrollOffsets)
    }

    /// Pastes `regions` (already copied, as `PasteRegions.pasted`) as `command` would.
    static func apply(_ command: PasteRegions, pasting regions: [Region], to project: Project) throws {
        let screen = try project.requireScreen(command.screen)
        for region in regions {
            attach(region, toParent: command.parent, in: screen)
            if command.parent == nil {
                place(region.id, in: screen, offsets: command.scrollOffsets)
            }
        }
    }

    static func apply(_ command: SetRegionScroll, to project: Project) throws {
        guard let (target, screen) = project.region(withID: command.region) else {
            throw EditError.regionNotFound(command.region)
        }
        target.scroll = command.scroll
        replaceChildrenOutsideContent(of: target, in: screen, offsets: command.scrollOffsets)
    }

    static func topmostRegions(_ ids: [RegionID], in index: RegionIndex) throws -> [Region] {
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

    // MARK: Parenting

    static func placement(
        forDrawn drawn: Frame, excluding: RegionID?, layout: ScrollLayout, keeping: RegionID? = nil
    ) -> Parenting.Placement {
        let index = layout.index
        var best: (region: Region, area: Int)?
        for region in index.regions {
            if let excluding, index.path(to: region.id).contains(where: { $0.id == excluding }) { continue }
            guard let content = layout.drawnContentArea(of: region.id), content.contains(drawn) else { continue }
            if region.scroll != nil, region.id != keeping {
                guard let frame = layout.drawnFrame(of: region.id), frame.intersects(drawn) else { continue }
            }
            if let current = best, current.area < region.frame.area { continue }
            best = (region, region.frame.area)
        }
        let parent = best?.region.id
        return Parenting.Placement(parent: parent, frame: layout.fileFrame(forDrawn: drawn, inParent: parent))
    }

    static func reparentAfterChange(
        of id: RegionID, in screen: Screen, offsets: [RegionID: ScrollOffset], keepingParent: Bool = false
    ) {
        place(id, in: screen, offsets: offsets, keepingParent: keepingParent)
        guard let region = RegionIndex(screen: screen).region(id) else { return }
        replaceChildrenOutsideContent(of: region, in: screen, offsets: offsets)
    }

    static func replaceChildrenOutsideContent(
        of region: Region, in screen: Screen, offsets: [RegionID: ScrollOffset]
    ) {
        let area = region.contentArea
        for child in region.children where !area.contains(child.frame) {
            place(child.id, in: screen, offsets: offsets)
        }
    }

    static func place(
        _ id: RegionID, in screen: Screen, offsets: [RegionID: ScrollOffset], keepingParent: Bool = false
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
        if let parent = index.parent(of: id) {
            parent.children.removeAll { $0.id == id }
        } else {
            screen.regions.removeAll { $0.id == id }
        }
        attach(entry.region, toParent: placement.parent, in: screen)
    }

    static func attach(_ region: Region, toParent parent: RegionID?, in screen: Screen) {
        if let parent, let parentRegion = RegionIndex(screen: screen).region(parent) {
            parentRegion.children.append(region)
        } else {
            screen.regions.append(region)
        }
    }
}
