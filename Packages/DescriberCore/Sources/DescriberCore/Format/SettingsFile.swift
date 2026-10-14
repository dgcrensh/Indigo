import Foundation

/// The app settings file, `settings.json` (spec 3 and 12). Every key is optional:
///
///     {
///       "defaultViewport": "ipad",
///       "gridSize": 16,
///       "snapping": false,
///       "viewportPresets": [
///         { "name": "Watch", "width": 198, "height": 242 }
///       ],
///       "keybinds": { "regionTool": "b", "zoomIn": ["cmd-+", "cmd-="], "followLink": [] }
///     }
///
/// Reading checks every value, and the first problem is an error naming its key; the app then keeps the settings it
/// had. Saving presets replaces `viewportPresets` and keeps every other key, in its order. A file that doesn't read
/// is never written.
public enum SettingsFile {
    public static let fileName = "settings.json"
    public static let defaultViewportKey = "defaultViewport"
    public static let gridSizeKey = "gridSize"
    public static let snappingKey = "snapping"
    public static let viewportPresetsKey = "viewportPresets"
    public static let keybindsKey = "keybinds"
    /// Every key the file can have, in the order the documentation lists them.
    public static let keys = [defaultViewportKey, gridSizeKey, snappingKey, viewportPresetsKey, keybindsKey]

    /// Why the settings file can't be used.
    public struct SettingsError: Error, Equatable, LocalizedError {
        public let message: String

        public init(_ message: String) {
            self.message = message
        }

        public var errorDescription: String? {
            "\(SettingsFile.fileName): \(message)"
        }
    }

    /// Every setting in the file, with the defaults for keys it doesn't have. A missing or blank file is the
    /// defaults. Throws for a file that doesn't parse, an unknown key, or a value the app can't use.
    public static func settings(in data: Data?) throws -> AppSettings {
        let pairs = try topLevel(data)
        if let unknown = pairs.first(where: { !keys.contains($0.key) }) {
            throw SettingsError(
                "“\(unknown.key)” isn’t a setting. The settings are \(list(keys.map { "“\($0)”" }, joinedBy: "and")).")
        }
        var seen: Set<String> = []
        if let repeated = pairs.first(where: { !seen.insert($0.key).inserted }) {
            throw SettingsError("“\(repeated.key)” appears more than once.")
        }
        let value = { (key: String) in pairs.first { $0.key == key }?.value }
        var settings = AppSettings()
        settings.viewportPresets = try viewportPresets(from: value(viewportPresetsKey))
        if let viewport = value(defaultViewportKey) {
            settings.defaultViewport = try defaultViewport(from: viewport, userPresets: settings.viewportPresets)
        }
        if let grid = value(gridSizeKey) {
            guard let size = wholeNumber(grid), Snapping.gridSteps.contains(size) else {
                let steps = list(Snapping.gridSteps.map(String.init), joinedBy: "or")
                throw SettingsError("“\(gridSizeKey)” should be one of \(steps).")
            }
            settings.gridSize = size
        }
        if let snapping = value(snappingKey) {
            guard case .bool(let on) = snapping else {
                throw SettingsError("“\(snappingKey)” should be true or false.")
            }
            settings.snapping = on
        }
        if let keybinds = value(keybindsKey) {
            settings.keybindOverrides = try keybindOverrides(from: keybinds)
        }
        return settings
    }

    /// The user presets in the file, or none when there is no file or it is empty. Only that key is checked.
    public static func viewportPresets(in data: Data?) throws -> [ViewportPreset] {
        try viewportPresets(from: try topLevel(data).first { $0.key == viewportPresetsKey }?.value)
    }

    private static func viewportPresets(from value: JSONValue?) throws -> [ViewportPreset] {
        guard let value else { return [] }
        guard case .array(let elements) = value else {
            throw SettingsError("“\(viewportPresetsKey)” should be a list of presets.")
        }
        let entries = try elements.enumerated().map { index, element in
            guard let entry = preset(from: element) else {
                throw SettingsError(
                    "\(viewportPresetsKey)[\(index)] needs a name, and a width and height of at least 1 point.")
            }
            return entry
        }
        return ViewportPresets.userPresets(entries)
    }

    /// Saves a preset named `name` at `width` × `height` into the file's contents, replacing one with the same name
    /// (ignoring case): the new contents, the settings they hold, and the saved preset. Throws, and returns nothing
    /// to write, when any value in the file is bad, so a file the app can't read is never rewritten.
    public static func savingViewportPreset(
        name: String, width: Int, height: Int, in data: Data?
    ) throws -> (data: Data, settings: AppSettings, preset: ViewportPreset) {
        let current = try settings(in: data)
        let presets = ViewportPresets.saving(name: name, width: width, height: height, in: current.viewportPresets)
        let written = try replacingViewportPresets(presets, in: data)
        let saved = try settings(in: written)
        let preset = saved.viewportPresets.first { $0.name.lowercased() == name.lowercased() }
        return (written, saved, preset ?? presets[presets.count - 1])
    }

    /// The file's contents with `viewportPresets` set to `presets`, every other key kept in its place. A missing or
    /// empty file starts from an empty object. Throws, and returns nothing to write, when the file doesn't read.
    public static func replacingViewportPresets(_ presets: [ViewportPreset], in data: Data?) throws -> Data {
        var pairs = try topLevel(data)
        let list = JSONValue.array(
            presets.map { preset in
                .object([
                    ("name", .string(preset.name)), ("width", .int(preset.width)), ("height", .int(preset.height)),
                ])
            })
        if let index = pairs.firstIndex(where: { $0.key == viewportPresetsKey }) {
            pairs[index].value = list
        } else {
            pairs.append((viewportPresetsKey, list))
        }
        return OrderedJSONWriter.data(.object(pairs))
    }

    private static func defaultViewport(
        from value: JSONValue, userPresets: [ViewportPreset]
    ) throws -> AppSettings.DefaultViewport {
        switch value {
        case .string(let name) where name.lowercased() == ViewportPresets.thisDeviceID:
            return .thisDevice
        case .string(let name):
            guard let preset = ViewportPresets.preset(named: name, userPresets: userPresets) else {
                throw SettingsError(
                    "“\(defaultViewportKey)” names “\(name)”, which isn’t a viewport preset. Use a preset’s name, "
                        + "“\(ViewportPresets.thisDeviceID)”, or { \"width\": …, \"height\": … }.")
            }
            return .viewport(preset.viewport)
        case .object(let pairs):
            guard pairs.allSatisfy({ ["width", "height"].contains($0.key) }),
                let width = points(pairs.first { $0.key == "width" }?.value),
                let height = points(pairs.first { $0.key == "height" }?.value)
            else {
                throw SettingsError(
                    "“\(defaultViewportKey)” needs a width and height of at least 1 point, such as "
                        + "{ \"width\": 500, \"height\": 400 }.")
            }
            return .viewport(Viewport(width: width, height: height))
        default:
            throw SettingsError(
                "“\(defaultViewportKey)” should be a preset’s name, “\(ViewportPresets.thisDeviceID)”, or "
                    + "{ \"width\": …, \"height\": … }.")
        }
    }

    private static func keybindOverrides(from value: JSONValue) throws -> [KeyAction: [KeyCombo]] {
        guard case .object(let pairs) = value else {
            throw SettingsError("“\(keybindsKey)” should map action names to keys, such as { \"regionTool\": \"b\" }.")
        }
        var overrides: [KeyAction: [KeyCombo]] = [:]
        var owners: [KeyCombo: KeyAction] = [:]
        for (name, entry) in pairs {
            guard let action = KeyAction(rawValue: name) else {
                throw SettingsError(
                    "\(keybindsKey): “\(name)” isn’t an action. The actions are listed in Schema/README.md.")
            }
            let texts: [JSONValue]
            switch entry {
            case .string: texts = [entry]
            case .array(let elements): texts = elements
            default:
                throw SettingsError("\(keybindsKey).\(name) should be a key, such as \"shift-d\", or a list of keys.")
            }
            var combos: [KeyCombo] = []
            for text in texts {
                guard case .string(let string) = text, let combo = KeyCombo(parsing: string) else {
                    let shown = if case .string(let string) = text { "“\(string)”" } else { "a value" }
                    throw SettingsError(
                        "\(keybindsKey).\(name) has \(shown), which isn’t a key. Keys look like “v”, “shift-d” or "
                            + "“cmd-option-left”.")
                }
                if let owner = owners[combo], owner != action {
                    throw SettingsError(
                        "\(keybindsKey) gives “\(combo)” to both “\(owner.rawValue)” and “\(name)”.")
                }
                owners[combo] = action
                if !combos.contains(combo) { combos.append(combo) }
            }
            overrides[action] = combos
        }
        return overrides
    }

    /// “a, b or c”.
    private static func list(_ items: [String], joinedBy word: String) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(word) " + items[items.count - 1]
    }

    private static func topLevel(_ data: Data?) throws -> [(key: String, value: JSONValue)] {
        guard let data, !String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) else { return [] }
        let value: JSONValue
        do {
            value = try JSONReader.parse(data)
        } catch let error as JSONReader.ParseError {
            throw SettingsError("line \(error.line): \(error.message)")
        }
        guard case .object(let pairs) = value else {
            throw SettingsError("the file should hold one JSON object, in { }.")
        }
        return pairs
    }

    private static func preset(from value: JSONValue) -> (name: String, width: Int, height: Int)? {
        guard case .object(let pairs) = value,
            case .string(let rawName) = pairs.first(where: { $0.key == "name" })?.value,
            let name = ScreenNames.cleaned(rawName),
            let width = points(pairs.first { $0.key == "width" }?.value),
            let height = points(pairs.first { $0.key == "height" }?.value)
        else { return nil }
        return (name, width, height)
    }

    /// A whole number of points, at least 1.
    private static func points(_ value: JSONValue?) -> Int? {
        wholeNumber(value).flatMap { $0 >= 1 ? $0 : nil }
    }

    /// An integer, or a number with nothing after the point, such as `16.0`.
    private static func wholeNumber(_ value: JSONValue?) -> Int? {
        switch value {
        case .int(let number):
            return number
        case .double(let number) where number == number.rounded() && abs(number) < 1e9:
            return Int(number)
        default:
            return nil
        }
    }
}
