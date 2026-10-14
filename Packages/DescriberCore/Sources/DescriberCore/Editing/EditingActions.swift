import Foundation

/// How far each arrow-key nudge moves the selection (spec Section 7).
public enum Nudge {
    /// The delta for a nudge action, or nil for any other action: one grid step, or four with Shift; 1 pt and 4 pt
    /// with snapping off.
    public static func delta(for action: KeyAction, grid: Int, snapping: Bool) -> (dx: Int, dy: Int)? {
        let step = Snapping.nudgeDistance(grid: grid, snapping: snapping, shift: false)
        let far = Snapping.nudgeDistance(grid: grid, snapping: snapping, shift: true)
        switch action {
        case .nudgeLeft: return (-step, 0)
        case .nudgeRight: return (step, 0)
        case .nudgeUp: return (0, -step)
        case .nudgeDown: return (0, step)
        case .nudgeLeftFar: return (-far, 0)
        case .nudgeRightFar: return (far, 0)
        case .nudgeUpFar: return (0, -far)
        case .nudgeDownFar: return (0, far)
        default: return nil
        }
    }
}

/// The question asked before deleting regions that have regions inside them (spec Section 7).
public enum DeleteConfirmation {
    /// Such as "Delete “Sign-in form” and the 2 regions inside it?", or nil when no region being deleted has
    /// children, so the delete needs no confirmation.
    public static func message(deleting selection: [RegionID], on screen: Screen) -> String? {
        let index = RegionIndex(screen: screen)
        var seen = Set<RegionID>()
        let ids = selection.filter { index.contains($0) && seen.insert($0).inserted }
        // Regions inside another selected region are counted as inside, not as deleted in their own right.
        let roots = ids.filter { id in !index.path(to: id).dropLast().contains { seen.contains($0.id) } }
        let inside = roots.reduce(0) { $0 + index.descendants(of: $1).count }
        guard inside > 0, let first = roots.first.flatMap(index.region) else { return nil }
        let insideText = inside == 1 ? "the region inside" : "the \(inside) regions inside"
        if roots.count == 1 {
            let name = first.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = name.isEmpty ? "this region" : "“\(name)”"
            return "Delete \(subject) and \(insideText) it?"
        }
        return "Delete \(roots.count) regions and \(insideText) them?"
    }
}

/// Which regions show their descriptions on the canvas (spec Sections 4 and 9). Editor state, so toggling it isn't
/// an edit.
public enum DescriptionVisibility {
    /// `visible` with `regions` hidden when every one of them is shown already, otherwise with all of them shown.
    /// `D` passes the selection and `Shift-D` every region on the screen.
    public static func toggling(_ regions: [RegionID], in visible: Set<RegionID>) -> Set<RegionID> {
        guard !regions.isEmpty else { return visible }
        if regions.allSatisfy(visible.contains) {
            return visible.subtracting(regions)
        }
        return visible.union(regions)
    }
}
