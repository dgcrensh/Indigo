import Foundation

/// Names for new and renamed screens.
public enum ScreenNames {
    /// "Screen 1", or the first "Screen N" no screen in the project is called yet.
    public static func newScreenName(in project: Project) -> String {
        let used = Set(project.screens.map { $0.name.lowercased() })
        var number = 1
        while used.contains("screen \(number)") {
            number += 1
        }
        return "Screen \(number)"
    }

    /// A typed name with the spaces and newlines around it trimmed, or nil when nothing is left, so a blank rename
    /// keeps the old name.
    public static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The question asked before deleting a screen other screens link to (spec 8.1).
public enum ScreenDeleteConfirmation {
    /// Such as "Delete “Reset Password”? 2 regions on other screens link to it, and those links will be removed.",
    /// or nil when no region on another screen links to it, so the delete needs no confirmation.
    public static func message(deleting screen: ScreenID, in project: Project) -> String? {
        guard let target = project.screen(withID: screen) else { return nil }
        let count = ScreenCommands.incomingLinks(to: screen, in: project).count
        guard count > 0 else { return nil }
        let name = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = name.isEmpty ? "this screen" : "“\(name)”"
        let linking =
            count == 1
            ? "1 region on another screen links to it, and that link will be removed."
            : "\(count) regions on other screens link to it, and those links will be removed."
        return "Delete \(subject)? \(linking)"
    }
}

/// Moving between screens in sidebar order.
public enum ScreenNavigation {
    /// The screen `offset` places after `screen` in the sidebar (before it for a negative offset), or nil past
    /// either end; Next and Previous Screen don't wrap around. With no screen, the first screen.
    public static func neighbor(of screen: ScreenID?, offset: Int, in project: Project) -> ScreenID? {
        let order = SidebarOutline(project: project).screens
        guard let screen, let index = order.firstIndex(of: screen) else { return order.first }
        let target = index + offset
        return order.indices.contains(target) ? order[target] : nil
    }

    /// The screen that takes the place of `removed` once it is gone: the nearest screen after it in
    /// `previousOrder` that is still in the project, otherwise the nearest before it, otherwise the first screen.
    public static func replacement(
        forRemoved removed: ScreenID, previousOrder: [ScreenID], in project: Project
    ) -> ScreenID? {
        let exists = Set(project.screens.map(\.id))
        if let index = previousOrder.firstIndex(of: removed) {
            if let after = previousOrder[(index + 1)...].first(where: exists.contains) {
                return after
            }
            if let before = previousOrder[..<index].last(where: exists.contains) {
                return before
            }
        }
        return SidebarOutline(project: project).screens.first
    }
}

/// One link a region can follow, as the link menu shows it.
public struct LinkTarget: Hashable, Sendable {
    public let screen: ScreenID
    /// The target screen's name, then the trigger when the link has one, such as "Reset Password — click".
    public let title: String

    public init(screen: ScreenID, title: String) {
        self.screen = screen
        self.title = title
    }
}

public enum LinkTargets {
    /// The region's links that point at screens in the project, in order (spec 8.4).
    public static func entries(for region: Region, in project: Project) -> [LinkTarget] {
        region.links.compactMap { link in
            guard let screen = project.screen(withID: link.screen) else { return nil }
            let trigger = link.trigger?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = trigger.isEmpty ? screen.name : "\(screen.name) — \(trigger)"
            return LinkTarget(screen: screen.id, title: title)
        }
    }
}

/// Link-following history, like a browser's (spec 8.4). Following a link puts the screen it was followed from on
/// the Back list and clears Forward. Screens deleted since are skipped. Editor state, so it isn't saved or undone.
public struct NavigationHistory: Equatable, Sendable {
    public private(set) var backList: [ScreenID] = []
    public private(set) var forwardList: [ScreenID] = []

    public init() {}

    /// Records following a link from `current` to `target`. Following a link to the screen already showing changes
    /// nothing.
    public mutating func visit(_ target: ScreenID, from current: ScreenID?) {
        guard target != current else { return }
        if let current {
            backList.append(current)
        }
        forwardList.removeAll()
    }

    /// The screen Back goes to from `current`, recording `current` for Forward, or nil when there is none.
    public mutating func back(from current: ScreenID?, in project: Project) -> ScreenID? {
        guard let target = Self.pop(&backList, skipping: current, in: project) else { return nil }
        if let current {
            forwardList.append(current)
        }
        return target
    }

    /// The screen Forward goes to from `current`, recording `current` for Back, or nil when there is none.
    public mutating func forward(from current: ScreenID?, in project: Project) -> ScreenID? {
        guard let target = Self.pop(&forwardList, skipping: current, in: project) else { return nil }
        if let current {
            backList.append(current)
        }
        return target
    }

    public func canGoBack(from current: ScreenID?, in project: Project) -> Bool {
        backList.contains { $0 != current && project.screen(withID: $0) != nil }
    }

    public func canGoForward(from current: ScreenID?, in project: Project) -> Bool {
        forwardList.contains { $0 != current && project.screen(withID: $0) != nil }
    }

    /// Takes entries off the end of `list` until one is a screen in the project other than `current`.
    private static func pop(_ list: inout [ScreenID], skipping current: ScreenID?, in project: Project) -> ScreenID? {
        while let last = list.popLast() {
            if last != current, project.screen(withID: last) != nil {
                return last
            }
        }
        return nil
    }
}
