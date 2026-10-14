import Foundation

/// Reads JSON text into a `JSONValue`, keeping each object's keys in the order the text has them, so a file written
/// back with `OrderedJSONWriter` keeps its keys where they were. Used for `settings.json`, which people edit by hand.
public enum JSONReader {
    public struct ParseError: Error, Equatable, LocalizedError {
        public let message: String
        /// The 1-based line the problem is on.
        public let line: Int

        public var errorDescription: String? {
            "Line \(line): \(message)"
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: Array(data))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw parser.error("Unexpected text after the end of the JSON value.") }
        return value
    }

    private struct Parser {
        static let maximumDepth = 512

        let bytes: [UInt8]
        var position = 0

        var isAtEnd: Bool { position >= bytes.count }

        func error(_ message: String) -> ParseError {
            let line = bytes[..<min(position, bytes.count)].reduce(1) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
            return ParseError(message: message, line: line)
        }

        mutating func skipWhitespace() {
            while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) {
                position += 1
            }
        }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < Self.maximumDepth else { throw error("The JSON is nested too deeply.") }
            guard position < bytes.count else { throw error("The file ends where a value was expected.") }
            switch bytes[position] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): return try literal("true", .bool(true))
            case UInt8(ascii: "f"): return try literal("false", .bool(false))
            case UInt8(ascii: "n"): return try literal("null", .null)
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default: throw error("Expected a value.")
            }
        }

        mutating func literal(_ word: String, _ value: JSONValue) throws -> JSONValue {
            let expected = Array(word.utf8)
            guard bytes.count - position >= expected.count,
                Array(bytes[position..<position + expected.count]) == expected
            else { throw error("Expected a value.") }
            position += expected.count
            return value
        }

        mutating func object(depth: Int) throws -> JSONValue {
            position += 1
            var pairs: [(key: String, value: JSONValue)] = []
            skipWhitespace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
                position += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else {
                    throw error("Expected a key in quotes.")
                }
                let key = try string()
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else {
                    throw error("Expected “:” after the key “\(key)”.")
                }
                position += 1
                skipWhitespace()
                pairs.append((key, try value(depth: depth + 1)))
                skipWhitespace()
                guard position < bytes.count else { throw error("The file ends inside an object.") }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                } else if bytes[position] == UInt8(ascii: "}") {
                    position += 1
                    return .object(pairs)
                } else {
                    throw error("Expected “,” or “}”.")
                }
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            position += 1
            var values: [JSONValue] = []
            skipWhitespace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
                position += 1
                return .array(values)
            }
            while true {
                skipWhitespace()
                values.append(try value(depth: depth + 1))
                skipWhitespace()
                guard position < bytes.count else { throw error("The file ends inside an array.") }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                } else if bytes[position] == UInt8(ascii: "]") {
                    position += 1
                    return .array(values)
                } else {
                    throw error("Expected “,” or “]”.")
                }
            }
        }

        mutating func string() throws -> String {
            position += 1
            var scalars = String.UnicodeScalarView()
            var run: [UInt8] = []
            func flush() {
                if !run.isEmpty {
                    scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
                    run.removeAll()
                }
            }
            while position < bytes.count {
                let byte = bytes[position]
                switch byte {
                case UInt8(ascii: "\""):
                    position += 1
                    flush()
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    flush()
                    position += 1
                    guard position < bytes.count else { break }
                    let escape = bytes[position]
                    position += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"): scalars.append(try unicodeEscape())
                    default:
                        position -= 1
                        throw error("Unknown escape “\\\(Character(Unicode.Scalar(escape)))” in a string.")
                    }
                case 0..<0x20:
                    throw error("A string has a line break or control character in it; use \\n instead.")
                default:
                    run.append(byte)
                    position += 1
                }
            }
            throw error("The file ends inside a string.")
        }

        /// The scalar after `\u`, joining a surrogate pair. A lone surrogate becomes U+FFFD.
        mutating func unicodeEscape() throws -> Unicode.Scalar {
            let high = try hexQuad()
            if (0xD800..<0xDC00).contains(high), bytes.count - position >= 6,
                bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u")
            {
                let saved = position
                position += 2
                let low = try hexQuad()
                if (0xDC00..<0xE000).contains(low) {
                    return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)) ?? "\u{FFFD}"
                }
                position = saved
            }
            return Unicode.Scalar(high) ?? "\u{FFFD}"
        }

        mutating func hexQuad() throws -> UInt32 {
            guard bytes.count - position >= 4 else { throw error("Expected four hex digits after \\u.") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = Character(Unicode.Scalar(bytes[position])).hexDigitValue else {
                    throw error("Expected four hex digits after \\u.")
                }
                value = value * 16 + UInt32(digit)
                position += 1
            }
            return value
        }

        mutating func number() throws -> JSONValue {
            let start = position
            func digits() -> Int {
                let begin = position
                while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) {
                    position += 1
                }
                return position - begin
            }
            if bytes[position] == UInt8(ascii: "-") {
                position += 1
            }
            let integerStart = position
            guard digits() > 0 else { throw error("Expected digits in a number.") }
            if position - integerStart > 1, bytes[integerStart] == UInt8(ascii: "0") {
                throw error("A number can't start with 0.")
            }
            var isInteger = true
            if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
                isInteger = false
                position += 1
                guard digits() > 0 else { throw error("Expected digits after the decimal point.") }
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
                isInteger = false
                position += 1
                if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-")
                {
                    position += 1
                }
                guard digits() > 0 else { throw error("Expected digits in the exponent.") }
            }
            let text = String(decoding: bytes[start..<position], as: UTF8.self)
            if isInteger, let integer = Int(text) {
                return .int(integer)
            }
            return .double(Double(text) ?? 0)
        }
    }
}
