import AppKit
import DescriberCore

extension KeyCombo {
    /// The combination a key-down event is, or nil for a key the registry has no name for.
    init?(event: NSEvent) {
        let modifiers = Modifiers(event.modifierFlags)
        if let named = Self.namedKeyCodes[event.keyCode] {
            self.init(named, modifiers)
            return
        }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), characters.count == 1 else {
            return nil
        }
        self.init(characters, modifiers)
    }

    /// Virtual key codes of the named keys. The keypad's Enter counts as Return.
    private static let namedKeyCodes: [UInt16: String] = [
        36: "return", 76: "return", 51: "delete", 117: "forward-delete", 53: "escape", 48: "tab", 49: "space",
        123: "left", 124: "right", 125: "down", 126: "up",
    ]

    /// The key equivalent and modifier mask a menu item shows for this combination.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        let key: String
        switch self.key {
        case "return": key = "\r"
        case "delete": key = "\u{8}"
        case "forward-delete": key = Self.functionKey(NSDeleteFunctionKey)
        case "escape": key = "\u{1b}"
        case "tab": key = "\t"
        case "space": key = " "
        case "left": key = Self.functionKey(NSLeftArrowFunctionKey)
        case "right": key = Self.functionKey(NSRightArrowFunctionKey)
        case "up": key = Self.functionKey(NSUpArrowFunctionKey)
        case "down": key = Self.functionKey(NSDownArrowFunctionKey)
        default: key = self.key
        }
        return (key, NSEvent.ModifierFlags(modifiers))
    }

    private static func functionKey(_ code: Int) -> String {
        Unicode.Scalar(UInt32(code)).map { String(Character($0)) } ?? ""
    }
}

extension KeyCombo.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: KeyCombo.Modifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}

extension NSMenuItem {
    /// Sets the key equivalent to the first combination the registry has for `action`, or none.
    func setKeyEquivalent(for action: KeyAction, in registry: KeybindRegistry = .defaults, index: Int = 0) {
        let combos = registry.combos(for: action)
        guard combos.indices.contains(index) else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
            return
        }
        let equivalent = combos[index].menuKeyEquivalent
        keyEquivalent = equivalent.key
        keyEquivalentModifierMask = equivalent.modifiers
    }
}
