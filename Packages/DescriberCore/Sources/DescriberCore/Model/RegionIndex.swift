import Foundation

/// Where every region on one screen sits in the tree. Built from the screen as it is now, so build a new one after
/// each command rather than keeping one across edits.
///
/// Entries are stored in draw order, so a region's subtree is the run of positions from its own to its `subtreeEnd`,
/// and walks over the screen read an array instead of hashing IDs.
public struct RegionIndex {
    public struct Entry {
        public let region: Region
        /// The parent region's ID, or nil for a top-level region.
        public let parent: RegionID?
        /// Position among its siblings; higher draws on top.
        public let siblingIndex: Int
        /// Position in a depth-first walk in sibling order. A higher value draws on top of every lower one.
        public let drawOrder: Int
        /// The draw order of the last region in this one's subtree: its own for a region without children.
        public fileprivate(set) var subtreeEnd: Int
        /// The parent's draw order, or nil for a top-level region.
        let parentPosition: Int?
    }

    /// Indexed by draw order.
    private var entries: [Entry] = []
    private var positions: [RegionID: Int] = [:]
    /// Every region, depth first in sibling order.
    public private(set) var regions: [Region] = []
    private var topLevelCount = 0

    public init(screen: Screen) {
        let count = Self.count(screen.regions)
        entries.reserveCapacity(count)
        positions.reserveCapacity(count)
        regions.reserveCapacity(count)
        add(screen.regions, parent: nil)
        topLevelCount = screen.regions.count
    }

    private static func count(_ regions: [Region]) -> Int {
        regions.reduce(regions.count) { $0 + count($1.children) }
    }

    /// `firstSibling` is the sibling index of the first of `siblings`.
    private mutating func add(_ siblings: [Region], parent: Int?, firstSibling: Int = 0) {
        for (offset, region) in siblings.enumerated() {
            let position = regions.count
            positions[region.id] = position
            entries.append(
                Entry(
                    region: region, parent: parent.map { regions[$0].id }, siblingIndex: firstSibling + offset, drawOrder: position,
                    subtreeEnd: position, parentPosition: parent))
            regions.append(region)
            add(region.children, parent: position)
            entries[position].subtreeEnd = regions.count - 1
        }
    }

    /// Adds `region` and its subtree as the last top-level region, as appending it to the screen's regions would.
    mutating func appendTopLevel(_ region: Region) {
        add([region], parent: nil, firstSibling: topLevelCount)
        topLevelCount += 1
    }

    public subscript(id: RegionID) -> Entry? {
        positions[id].map { entries[$0] }
    }

    /// The entry at draw order `position`.
    subscript(position position: Int) -> Entry {
        entries[position]
    }

    /// `id`'s draw order, or nil when it isn't on the screen.
    public func position(of id: RegionID) -> Int? {
        positions[id]
    }

    public func region(_ id: RegionID) -> Region? {
        positions[id].map { regions[$0] }
    }

    public func contains(_ id: RegionID) -> Bool {
        positions[id] != nil
    }

    public func parent(of id: RegionID) -> Region? {
        positions[id].flatMap { entries[$0].parentPosition }.map { regions[$0] }
    }

    /// Every region below `id`, depth first in sibling order, not including `id` itself.
    public func descendants(of id: RegionID) -> [Region] {
        guard let position = positions[id] else { return [] }
        return Array(regions[(position + 1)..<(entries[position].subtreeEnd + 1)])
    }

    /// The regions from the top level down to `id`, inclusive.
    public func path(to id: RegionID) -> [Region] {
        var path: [Region] = []
        var current = positions[id]
        while let position = current {
            path.append(regions[position])
            current = entries[position].parentPosition
        }
        return path.reversed()
    }

    /// Whether `id` is `ancestor` or lies anywhere below it.
    public func isDescendant(_ id: RegionID, of ancestor: RegionID) -> Bool {
        guard let position = positions[id], let ancestorPosition = positions[ancestor] else { return false }
        return ancestorPosition <= position && position <= entries[ancestorPosition].subtreeEnd
    }

    /// Whether any region strictly above `id` in the tree is in `ids`.
    public func isInside(_ id: RegionID, anyOf ids: Set<RegionID>) -> Bool {
        var current = positions[id].flatMap { entries[$0].parentPosition }
        while let position = current {
            if ids.contains(regions[position].id) { return true }
            current = entries[position].parentPosition
        }
        return false
    }
}
