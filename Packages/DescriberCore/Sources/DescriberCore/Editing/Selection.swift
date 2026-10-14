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
}
