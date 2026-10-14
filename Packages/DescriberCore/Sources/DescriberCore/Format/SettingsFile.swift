import Foundation

/// The app settings file, `settings.json` (spec 3 and 12). This milestone reads and writes only the user viewport
/// presets, under `viewportPresets`:
///
///     {
///       "viewportPresets": [
///         { "name": "Watch", "width": 198, "height": 242 }
///       ]
///     }
///
/// Saving replaces that one key and keeps every other key, in its order. A file that doesn't read is never written.
public enum SettingsFile {
    public static let fileName = "settings.json"
    public static let viewportPresetsKey = "viewportPresets"

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

    /// The user presets in the file, or none when there is no file or it is empty.
    public static func viewportPresets(in data: Data?) throws -> [ViewportPreset] {
        let pairs = try topLevel(data)
        guard let value = pairs.first(where: { $0.key == viewportPresetsKey })?.value else { return [] }
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
        switch value {
        case .int(let number) where number >= 1:
            return number
        case .double(let number) where number >= 1 && number == number.rounded() && number < 1e9:
            return Int(number)
        default:
            return nil
        }
    }
}
