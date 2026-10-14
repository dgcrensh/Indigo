import Foundation

/// Helpers for the canvas selection: an ordered list of region IDs on the active screen, with no repeats. The
/// selection is editor state, so changing it isn't an edit and doesn't go through a command.
public enum Selection {
    /// `selection` with `id` removed if it was there, otherwise added at the end.
    public static func toggling(_ id: RegionID, in selection: [RegionID]) -> [RegionID] {
        selection.contains(id) ? selection.filter { $0 != id } : selection + [id]
    }

    /// `selection` followed by the IDs in `added` that it doesn't have yet.
    public static func adding(_ added: [RegionID], to selection: [RegionID]) -> [RegionID] {
        var seen = Set(selection)
        return selection + added.filter { seen.insert($0).inserted }
    }

    /// The selected regions that are still on `screen`, in the same order. Used after undo, redo or any edit that
    /// can remove regions.
    public static func pruned(_ selection: [RegionID], to screen: Screen) -> [RegionID] {
        let index = RegionIndex(screen: screen)
        return selection.filter { index.contains($0) }
    }

    /// Every region on `screen`, in draw order: what Select All selects (spec Section 7).
    public static func all(on screen: Screen) -> [RegionID] {
        screen.allRegions.map(\.id)
    }

    /// The parents of the selected regions, without repeats, in selection order: what Select Parent selects. A
    /// top-level region has no parent and adds nothing, so a selection of only top-level regions gives none.
    public static func parents(of selection: [RegionID], on screen: Screen) -> [RegionID] {
        let index = RegionIndex(screen: screen)
        return adding(selection.compactMap { index[$0]?.parent }, to: [])
    }

    /// The direct children of the selected regions, without repeats, in selection then sibling order: what Select
    /// Children selects.
    public static func children(of selection: [RegionID], on screen: Screen) -> [RegionID] {
        let index = RegionIndex(screen: screen)
        return adding(selection.flatMap { index.region($0)?.children.map(\.id) ?? [] }, to: [])
    }
}
