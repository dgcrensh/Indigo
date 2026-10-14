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
}
