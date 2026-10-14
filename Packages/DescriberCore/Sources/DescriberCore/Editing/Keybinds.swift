import Foundation

/// A key and the modifiers held with it, such as `cmd-option-left`. The app turns key events and menu key
/// equivalents into these; the core decides what they mean.
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// Keys that aren't a single printable character.
    public static let namedKeys: Set<String> = [
        "return", "delete", "forward-delete", "escape", "tab", "space", "left", "right", "up", "down",
    ]

    /// A lowercase character, such as `v` or `]`, or one of `namedKeys`.
    public let key: String
    public let modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    /// Reads the settings form: modifiers then the key, joined by `-`, such as `v`, `shift-d`, `cmd-option-left` or
    /// `cmd--` (Cmd and the minus key). Case doesn't matter; `command`, `alt` and `control` are accepted too.
    public init?(parsing string: String) {
        var text = string.lowercased()
        var key: String
        if let named = Self.namedKeys.first(where: { $0.contains("-") && (text == $0 || text.hasSuffix("-" + $0)) }) {
            key = named
            text = String(text.dropLast(min(text.count, named.count + 1)))
        } else if text == "-" || text.hasSuffix("--") {
            key = "-"
            text = String(text.dropLast(text == "-" ? 1 : 2))
        } else {
            guard let last = text.split(separator: "-", omittingEmptySubsequences: false).last else { return nil }
            key = String(last)
            text = String(text.dropLast(key.count))
            if text.hasSuffix("-") { text.removeLast() }
        }
        guard key.count == 1 || Self.namedKeys.contains(key) else { return nil }
        if key == " " { key = "space" }
        var modifiers: Modifiers = []
        if !text.isEmpty {
            for name in text.split(separator: "-", omittingEmptySubsequences: false) {
                switch name {
                case "cmd", "command": modifiers.insert(.command)
                case "shift": modifiers.insert(.shift)
                case "option", "alt": modifiers.insert(.option)
                case "ctrl", "control": modifiers.insert(.control)
                default: return nil
                }
            }
        }
        self.init(key, modifiers)
    }

    /// The settings form, such as `cmd-option-left`. `KeyCombo(parsing:)` reads it back.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "-")
    }

    /// The form menus and toasts show, such as `R`, `⇧D` or `⌘⌥←`.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case "return": text += "↩"
        case "delete": text += "⌫"
        case "forward-delete": text += "⌦"
        case "escape": text += "⎋"
        case "tab": text += "⇥"
        case "space": text += "Space"
        case "left": text += "←"
        case "right": text += "→"
        case "up": text += "↑"
        case "down": text += "↓"
        default: text += key.uppercased()
        }
        return text
    }
}

/// Every keybind action in spec Section 9. Holding Option to invert snapping isn't here: it is a modifier read
/// during a gesture, not a key that triggers something.
public enum KeyAction: String, CaseIterable, Sendable {
    case selectTool
    case regionTool
    case writeTool
    case toggleSnapping
    case gridSize
    case toggleDescription
    case toggleAllDescriptions
    case selectParent
    case selectChildren
    case selectAll
    case copy
    case paste
    case duplicate
    case nudgeLeft
    case nudgeRight
    case nudgeUp
    case nudgeDown
    case nudgeLeftFar
    case nudgeRightFar
    case nudgeUpFar
    case nudgeDownFar
    case delete
    case undo
    case redo
    case bringToFront
    case sendToBack
    case followLink
    case back
    case forward
    case nextScreen
    case previousScreen
    case toggleSidebar
    case zoomIn
    case zoomOut
    case actualSize

    /// The standard editing shortcuts that keep working while a text field is being edited (spec 6.3).
    public var worksWhileEditingText: Bool {
        switch self {
        case .undo, .redo, .copy, .paste, .selectAll: true
        default: false
        }
    }
}

/// Maps actions to key combinations: the spec Section 9 defaults with any overrides from settings on top.
public struct KeybindRegistry: Sendable {
    /// Spec Section 9.
    public static let defaultCombos: [KeyAction: [KeyCombo]] = [
        .selectTool: [KeyCombo("v")],
        .regionTool: [KeyCombo("r")],
        .writeTool: [KeyCombo("w")],
        .toggleSnapping: [KeyCombo("s")],
        .gridSize: [KeyCombo("g")],
        .toggleDescription: [KeyCombo("d")],
        .toggleAllDescriptions: [KeyCombo("d", .shift)],
        .selectParent: [KeyCombo("return", .shift)],
        .selectChildren: [KeyCombo("return")],
        .selectAll: [KeyCombo("a", .command)],
        .copy: [KeyCombo("c", .command)],
        .paste: [KeyCombo("v", .command)],
        .duplicate: [KeyCombo("d", .command)],
        .nudgeLeft: [KeyCombo("left")],
        .nudgeRight: [KeyCombo("right")],
        .nudgeUp: [KeyCombo("up")],
        .nudgeDown: [KeyCombo("down")],
        .nudgeLeftFar: [KeyCombo("left", .shift)],
        .nudgeRightFar: [KeyCombo("right", .shift)],
        .nudgeUpFar: [KeyCombo("up", .shift)],
        .nudgeDownFar: [KeyCombo("down", .shift)],
        .delete: [KeyCombo("delete"), KeyCombo("forward-delete")],
        .undo: [KeyCombo("z", .command)],
        .redo: [KeyCombo("z", [.command, .shift])],
        .bringToFront: [KeyCombo("]", .command)],
        .sendToBack: [KeyCombo("[", .command)],
        .followLink: [KeyCombo("l")],
        .back: [KeyCombo("left", [.command, .option])],
        .forward: [KeyCombo("right", [.command, .option])],
        .nextScreen: [KeyCombo("down", [.command, .option])],
        .previousScreen: [KeyCombo("up", [.command, .option])],
        .toggleSidebar: [KeyCombo("s", [.control, .command])],
        // Cmd = is the same key as Cmd + without Shift, so it zooms in too.
        .zoomIn: [KeyCombo("+", .command), KeyCombo("=", .command)],
        .zoomOut: [KeyCombo("-", .command)],
        .actualSize: [KeyCombo("0", .command)],
    ]

    public static let defaults = KeybindRegistry()

    private let combosByAction: [KeyAction: [KeyCombo]]
    private let actionsByCombo: [KeyCombo: KeyAction]

    /// The defaults with `overrides` on top. An override replaces all of an action's combinations, and a
    /// combination an override uses is taken away from the action that had it by default.
    public init(overrides: [KeyAction: [KeyCombo]] = [:]) {
        let claimed = Set(overrides.values.flatMap { $0 })
        var combosByAction: [KeyAction: [KeyCombo]] = [:]
        var actionsByCombo: [KeyCombo: KeyAction] = [:]
        for action in KeyAction.allCases {
            let combos =
                overrides[action] ?? (Self.defaultCombos[action] ?? []).filter { !claimed.contains($0) }
            combosByAction[action] = combos
            for combo in combos where actionsByCombo[combo] == nil {
                actionsByCombo[combo] = action
            }
        }
        self.combosByAction = combosByAction
        self.actionsByCombo = actionsByCombo
    }

    /// The combinations that trigger `action`; the first is the one menus show.
    public func combos(for action: KeyAction) -> [KeyCombo] {
        combosByAction[action] ?? []
    }

    /// The action `combo` triggers. While a text field is being edited, only the standard editing shortcuts resolve
    /// (spec 6.3), so no canvas or tool keybind fires.
    public func action(for combo: KeyCombo, isEditingText: Bool = false) -> KeyAction? {
        guard let action = actionsByCombo[combo] else { return nil }
        if isEditingText && !action.worksWhileEditingText { return nil }
        return action
    }
}
