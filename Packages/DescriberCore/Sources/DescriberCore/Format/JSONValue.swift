import Foundation

/// A JSON value whose objects keep their keys in the order given, so the writer controls key order.
public enum JSONValue: Hashable, Sendable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.array(let a), .array(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .object(let pairs):
            hasher.combine(0)
            for pair in pairs {
                hasher.combine(pair.key)
                hasher.combine(pair.value)
            }
        case .array(let values):
            hasher.combine(1)
            hasher.combine(values)
        case .string(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .int(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .double(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .null:
            hasher.combine(6)
        }
    }

    /// Whether the two values write to the same text. Stricter than `==`, which treats canonically equivalent
    /// strings such as a precomposed and a decomposed "é" as equal although their bytes differ.
    func isIdentical(to other: JSONValue) -> Bool {
        switch (self, other) {
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { Self.sameBytes($0.key, $1.key) && $0.value.isIdentical(to: $1.value) }
        case (.array(let a), .array(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.isIdentical(to: $1) }
        case (.string(let a), .string(let b)): return Self.sameBytes(a, b)
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a.bitPattern == b.bitPattern
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    private static func sameBytes(_ a: String, _ b: String) -> Bool {
        guard a.utf8.count == b.utf8.count else { return false }
        var a = a
        var b = b
        return a.withUTF8 { a in
            b.withUTF8 { b in a.count == 0 || memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 }
        }
    }
}
