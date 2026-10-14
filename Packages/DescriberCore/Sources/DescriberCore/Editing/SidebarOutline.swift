import Foundation

/// What the screen sidebar shows: the screens in project order, with each variant group's screens pulled together at
/// the place of its first screen (spec 8.3), and a header row above each group. Commands that add or group screens
/// keep the project in this order, so the file order and the sidebar order agree.
public struct SidebarOutline: Equatable, Sendable {
    public enum Row: Hashable, Sendable {
        /// The header of `project.variantGroups[index]`.
        case group(Int)
        /// A screen, and the index of the variant group it is in.
        case screen(ScreenID, group: Int?)

        public var screen: ScreenID? {
            if case .screen(let id, _) = self { return id }
            return nil
        }
    }

    /// Every screen in sidebar order.
    public let screens: [ScreenID]
    /// The rows the sidebar draws, in order.
    public let rows: [Row]
    /// The project's variant groups, which `Row.group` indexes.
    public let groups: [VariantGroup]

    public init(project: Project) {
        let groups = project.variantGroups
        self.groups = groups
        screens = Self.grouping(project.screens.map(\.id), groups: groups)
        var rows: [Row] = []
        var lastGroup: Int?
        for id in screens {
            let group = Self.group(of: id, in: groups)
            if let group, group != lastGroup {
                rows.append(.group(group))
            }
            rows.append(.screen(id, group: group))
            lastGroup = group
        }
        self.rows = rows
    }

    /// The screen order after the screen rows at `moved` (row indices) are dragged to just before row `destination`
    /// (`rows.count` for the end), as a list's move reports it. Header rows can't be dragged and are ignored. Groups are
    /// pulled together again afterwards: a group with a dragged screen gathers where that screen was dropped, so
    /// dragging a group's screen within it reorders the group and dragging it away takes the group along; a screen
    /// dropped among a group it isn't in lands after the group.
    public func order(afterMoving moved: [Int], to destination: Int) -> [ScreenID] {
        let movedSet = Set(moved.filter { rows.indices.contains($0) && rows[$0].screen != nil })
        let movedRows = rows.indices.filter(movedSet.contains).map { rows[$0] }
        var remaining: [Row] = []
        var insertAt = 0
        for (index, row) in rows.enumerated() where !movedSet.contains(index) {
            if index < destination {
                insertAt += 1
            }
            remaining.append(row)
        }
        remaining.insert(contentsOf: movedRows, at: min(insertAt, remaining.count))
        let anchors = Set(movedRows.compactMap(\.screen))
        return Self.grouping(remaining.compactMap(\.screen), groups: groups, anchors: anchors)
    }

    /// The index of the variant group `screen` is in.
    public static func group(of screen: ScreenID, in groups: [VariantGroup]) -> Int? {
        groups.firstIndex { $0.screens.contains(screen) }
    }

    /// `order` with each group's screens gathered at the place of its first screen, or of its first screen in
    /// `anchors` when it has one, keeping their order among themselves.
    static func grouping(_ order: [ScreenID], groups: [VariantGroup], anchors: Set<ScreenID> = []) -> [ScreenID] {
        var result: [ScreenID] = []
        var placed = Set<ScreenID>()
        for id in order where !placed.contains(id) {
            if let group = group(of: id, in: groups) {
                let members = groups[group].screens
                // A group with a dragged screen waits for it.
                if !anchors.contains(id), members.contains(where: anchors.contains) {
                    continue
                }
                for member in order where members.contains(member) && !placed.contains(member) {
                    result.append(member)
                    placed.insert(member)
                }
            } else {
                result.append(id)
                placed.insert(id)
            }
        }
        return result
    }
}

extension Project {
    /// Reorders `screens` to the sidebar order, so each variant group's screens sit together.
    func groupVariantScreens() {
        let order = SidebarOutline.grouping(screens.map(\.id), groups: variantGroups)
        let byID = Dictionary(uniqueKeysWithValues: screens.map { ($0.id, $0) })
        screens = order.compactMap { byID[$0] }
    }
}
