import Foundation

/// Where every region on one screen sits in the tree. Built from the screen as it is now, so build a new one after
/// each command rather than keeping one across edits.
public struct RegionIndex {
    public struct Entry {
        public let region: Region
        /// The parent region's ID, or nil for a top-level region.
        public let parent: RegionID?
        /// Position among its siblings; higher draws on top.
        public let siblingIndex: Int
        /// Position in a depth-first walk in sibling order. A higher value draws on top of every lower one.
        public let drawOrder: Int
    }

    private var entries: [RegionID: Entry] = [:]
    /// Every region, depth first in sibling order.
    public private(set) var regions: [Region] = []

    public init(screen: Screen) {
        add(screen.regions, parent: nil)
    }

    private mutating func add(_ siblings: [Region], parent: RegionID?) {
        for (index, region) in siblings.enumerated() {
            entries[region.id] = Entry(region: region, parent: parent, siblingIndex: index, drawOrder: regions.count)
            regions.append(region)
            add(region.children, parent: region.id)
        }
    }

    public subscript(id: RegionID) -> Entry? {
        entries[id]
    }

    public func region(_ id: RegionID) -> Region? {
        entries[id]?.region
    }

    public func contains(_ id: RegionID) -> Bool {
        entries[id] != nil
    }

    public func parent(of id: RegionID) -> Region? {
        entries[id]?.parent.flatMap(region)
    }

    /// Every region below `id`, depth first in sibling order, not including `id` itself.
    public func descendants(of id: RegionID) -> [Region] {
        guard let region = region(id) else { return [] }
        return Array(region.subtree.dropFirst())
    }

    /// The regions from the top level down to `id`, inclusive.
    public func path(to id: RegionID) -> [Region] {
        var path: [Region] = []
        var current = entries[id]
        while let entry = current {
            path.insert(entry.region, at: 0)
            current = entry.parent.flatMap { entries[$0] }
        }
        return path
    }

    /// Whether `id` is `ancestor` or lies anywhere below it.
    public func isDescendant(_ id: RegionID, of ancestor: RegionID) -> Bool {
        path(to: id).contains { $0.id == ancestor }
    }
}
