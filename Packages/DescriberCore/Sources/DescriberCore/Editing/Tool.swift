import Foundation

/// The active editing mode (spec Section 5). It decides what clicks and drags on the canvas do.
public enum Tool: String, CaseIterable, Sendable {
    case select
    case region
    case write

    /// The name toasts and menus use, such as "Region tool".
    public var name: String {
        switch self {
        case .select: "Select tool"
        case .region: "Region tool"
        case .write: "Write tool"
        }
    }

    /// The keybind that picks this tool.
    public var keyAction: KeyAction {
        switch self {
        case .select: .selectTool
        case .region: .regionTool
        case .write: .writeTool
        }
    }
}

/// The text of a toast: the small label that confirms a mode change on the canvas (spec Section 4).
public enum Toast: Hashable, Sendable {
    case tool(Tool)
    case snapping(on: Bool)
    case gridSize(Int)

    /// Such as "Region tool — R", with the key the registry has for the change.
    public func text(keybinds: KeybindRegistry = .defaults) -> String {
        switch self {
        case .tool(let tool):
            return Self.withKey(tool.name, keybinds.combos(for: tool.keyAction).first)
        case .snapping(let on):
            return Self.withKey(on ? "Snapping on" : "Snapping off", keybinds.combos(for: .toggleSnapping).first)
        case .gridSize(let size):
            return "Grid \(size) pt"
        }
    }

    private static func withKey(_ text: String, _ combo: KeyCombo?) -> String {
        guard let combo else { return text }
        return "\(text) — \(combo.displayString)"
    }
}

/// The tooltips of the tool pill's buttons, naming the key that does the same, such as "Region tool (R)".
public enum ToolPillTooltip {
    public static func text(for tool: Tool, keybinds: KeybindRegistry = .defaults) -> String {
        withKey(tool.name, keybinds.combos(for: tool.keyAction).first)
    }

    /// The snap button's: what a click does, and what an Option-click does.
    public static func snapping(keybinds: KeybindRegistry = .defaults) -> String {
        let snapping = withKey("Snapping", keybinds.combos(for: .toggleSnapping).first)
        let grid = withKey("Option-click for grid size", keybinds.combos(for: .gridSize).first)
        return "\(snapping). \(grid)"
    }

    private static func withKey(_ text: String, _ combo: KeyCombo?) -> String {
        guard let combo else { return text }
        return "\(text) (\(combo.displayString))"
    }
}
