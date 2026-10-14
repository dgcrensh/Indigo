import Foundation

/// Writes a `JSONValue` in the package's fixed formatting: 2-space indent, one key or element per line,
/// `"key": value`, empty containers as `[]` and `{}`, integers without a decimal point, and a trailing newline.
/// Key order is exactly the order in each `.object`.
public enum OrderedJSONWriter {
    public static func data(_ value: JSONValue) -> Data {
        Data(string(value).utf8)
    }

    public static func string(_ value: JSONValue) -> String {
        var output = ""
        write(value, indent: 0, to: &output)
        output += "\n"
        return output
    }

    private static func write(_ value: JSONValue, indent: Int, to output: inout String) {
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, pair) in pairs.enumerated() {
                output += padding(indent + 1)
                output += quoted(pair.key)
                output += ": "
                write(pair.value, indent: indent + 1, to: &output)
                output += index < pairs.count - 1 ? ",\n" : "\n"
            }
            output += padding(indent) + "}"
        case .array(let values):
            guard !values.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, element) in values.enumerated() {
                output += padding(indent + 1)
                write(element, indent: indent + 1, to: &output)
                output += index < values.count - 1 ? ",\n" : "\n"
            }
            output += padding(indent) + "]"
        case .string(let string):
            output += quoted(string)
        case .int(let number):
            output += String(number)
        case .double(let number):
            output += format(number)
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private static func padding(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }

    /// Doubles with no fractional part are written as integers; others use Swift's shortest round-tripping form.
    /// Non-finite values have no JSON form and are written as `0`.
    private static func format(_ number: Double) -> String {
        guard number.isFinite else { return "0" }
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int(number))
        }
        return String(number)
    }

    /// Escapes a string the way `JSONSerialization` does with `.withoutEscapingSlashes`: quote, backslash, and
    /// control characters are escaped; everything else, including non-ASCII, is written as is.
    static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case let control where control.value < 0x20:
                result += String(format: "\\u%04x", control.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
