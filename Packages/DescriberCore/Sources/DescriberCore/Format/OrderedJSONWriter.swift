import Foundation

/// Writes a `JSONValue` in the package's fixed formatting: 2-space indent, one key or element per line,
/// `"key": value`, empty containers as `[]` and `{}`, integers without a decimal point, and a trailing newline.
/// Key order is exactly the order in each `.object`.
public enum OrderedJSONWriter {
    public static func data(_ value: JSONValue) -> Data {
        Data(bytes(value))
    }

    public static func string(_ value: JSONValue) -> String {
        String(decoding: bytes(value), as: UTF8.self)
    }

    /// The text as UTF-8, written into one buffer.
    static func bytes(_ value: JSONValue) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(16 * 1024)
        write(value, indent: 0, to: &output)
        output.append(newline)
        return output
    }

    private static let newline = UInt8(ascii: "\n")
    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")

    /// Indents by level, built once; deeper levels are padded on the fly.
    private static let indents: [[UInt8]] = (0..<32).map { [UInt8](repeating: UInt8(ascii: " "), count: $0 * 2) }

    private static func write(_ value: JSONValue, indent: Int, to output: inout [UInt8]) {
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else {
                output.append(contentsOf: "{}".utf8)
                return
            }
            output.append(contentsOf: "{\n".utf8)
            for (index, pair) in pairs.enumerated() {
                pad(indent + 1, to: &output)
                writeQuoted(pair.key, to: &output)
                output.append(contentsOf: ": ".utf8)
                write(pair.value, indent: indent + 1, to: &output)
                if index < pairs.count - 1 {
                    output.append(UInt8(ascii: ","))
                }
                output.append(newline)
            }
            pad(indent, to: &output)
            output.append(UInt8(ascii: "}"))
        case .array(let values):
            guard !values.isEmpty else {
                output.append(contentsOf: "[]".utf8)
                return
            }
            output.append(contentsOf: "[\n".utf8)
            for (index, element) in values.enumerated() {
                pad(indent + 1, to: &output)
                write(element, indent: indent + 1, to: &output)
                if index < values.count - 1 {
                    output.append(UInt8(ascii: ","))
                }
                output.append(newline)
            }
            pad(indent, to: &output)
            output.append(UInt8(ascii: "]"))
        case .string(let string):
            writeQuoted(string, to: &output)
        case .int(let number):
            output.append(contentsOf: String(number).utf8)
        case .double(let number):
            output.append(contentsOf: format(number).utf8)
        case .bool(let flag):
            output.append(contentsOf: (flag ? "true" : "false").utf8)
        case .null:
            output.append(contentsOf: "null".utf8)
        }
    }

    private static func pad(_ level: Int, to output: inout [UInt8]) {
        if level < indents.count {
            output.append(contentsOf: indents[level])
        } else {
            output.append(contentsOf: repeatElement(UInt8(ascii: " "), count: level * 2))
        }
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
        var output: [UInt8] = []
        writeQuoted(string, to: &output)
        return String(decoding: output, as: UTF8.self)
    }

    private static func writeQuoted(_ string: String, to output: inout [UInt8]) {
        output.append(quote)
        var string = string
        string.withUTF8 { bytes in
            if !bytes.contains(where: needsEscaping) {
                output.append(contentsOf: bytes)
            } else {
                for byte in bytes {
                    appendEscaped(byte, to: &output)
                }
            }
        }
        output.append(quote)
    }

    /// Only ASCII bytes are ever escaped, so non-ASCII UTF-8 sequences pass through byte by byte unchanged.
    private static func needsEscaping(_ byte: UInt8) -> Bool {
        byte < 0x20 || byte == quote || byte == backslash
    }

    private static func appendEscaped(_ byte: UInt8, to output: inout [UInt8]) {
        switch byte {
        case quote: output.append(contentsOf: "\\\"".utf8)
        case backslash: output.append(contentsOf: "\\\\".utf8)
        case newline: output.append(contentsOf: "\\n".utf8)
        case UInt8(ascii: "\r"): output.append(contentsOf: "\\r".utf8)
        case UInt8(ascii: "\t"): output.append(contentsOf: "\\t".utf8)
        case 0x08: output.append(contentsOf: "\\b".utf8)
        case 0x0C: output.append(contentsOf: "\\f".utf8)
        case let control where control < 0x20:
            output.append(contentsOf: "\\u00".utf8)
            output.append(hexDigits[Int(control >> 4)])
            output.append(hexDigits[Int(control & 0x0F)])
        default:
            output.append(byte)
        }
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)
}
