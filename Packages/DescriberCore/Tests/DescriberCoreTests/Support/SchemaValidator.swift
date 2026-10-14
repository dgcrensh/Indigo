import Foundation

/// A small JSON Schema validator for the keywords `Schema/uidesc-1.schema.json` uses: `$ref` to `#/$defs/…`,
/// `oneOf`, `type`, `const`, `enum`, `properties`, `required`, `additionalProperties: false`, `items`,
/// `minItems`, `minimum`, and `pattern`. Annotation keywords are ignored. An unsupported keyword is reported as
/// an error, so the schema can't silently outgrow the validator.
struct SchemaValidator {
    private let root: [String: Any]

    private static let supported: Set<String> = [
        "$schema", "$id", "$defs", "$ref", "title", "description", "oneOf", "type", "const", "enum", "properties",
        "required", "additionalProperties", "items", "minItems", "minimum", "pattern",
    ]

    init(schema: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: schema) as? [String: Any] else {
            throw ValidationError(path: "", message: "schema is not an object")
        }
        self.root = root
    }

    struct ValidationError: Error, CustomStringConvertible {
        var path: String
        var message: String
        var description: String { "\(path.isEmpty ? "/" : path): \(message)" }
    }

    /// Errors for `instance`, or an empty array when it is valid.
    func validate(_ instance: Data) throws -> [ValidationError] {
        let value = try JSONSerialization.jsonObject(with: instance, options: [.fragmentsAllowed])
        return validate(value, against: root, path: "")
    }

    private func resolve(_ reference: String) -> [String: Any]? {
        guard reference.hasPrefix("#/") else { return nil }
        var node: Any = root
        for part in reference.dropFirst(2).split(separator: "/") {
            guard let object = node as? [String: Any], let next = object[String(part)] else { return nil }
            node = next
        }
        return node as? [String: Any]
    }

    private func validate(_ value: Any, against schema: [String: Any], path: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        func fail(_ message: String) { errors.append(ValidationError(path: path, message: message)) }

        for key in schema.keys where !Self.supported.contains(key) {
            fail("schema uses unsupported keyword \(key)")
        }
        if let reference = schema["$ref"] as? String {
            guard let target = resolve(reference) else {
                fail("unresolvable $ref \(reference)")
                return errors
            }
            errors += validate(value, against: target, path: path)
        }
        if let options = schema["oneOf"] as? [[String: Any]] {
            let matches = options.filter { validate(value, against: $0, path: path).isEmpty }.count
            if matches != 1 { fail("matches \(matches) of the oneOf schemas, expected exactly 1") }
        }
        if let type = schema["type"] as? String, !Self.matches(value, type: type) {
            fail("expected \(type)")
            return errors
        }
        if let constant = schema["const"], !Self.equal(value, constant) {
            fail("expected \(constant)")
        }
        if let options = schema["enum"] as? [Any], !options.contains(where: { Self.equal(value, $0) }) {
            fail("\(value) is not one of \(options)")
        }
        if let minimum = schema["minimum"] as? Double, let number = Self.number(value), number < minimum {
            fail("\(number) is less than \(minimum)")
        }
        if let pattern = schema["pattern"] as? String, let string = value as? String,
            string.range(of: pattern, options: .regularExpression) == nil
        {
            fail("\"\(string)\" does not match \(pattern)")
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                fail("missing required property \(key)")
            }
            for (key, child) in object {
                if let propertySchema = properties[key] {
                    errors += validate(child, against: propertySchema, path: "\(path)/\(key)")
                } else if schema["additionalProperties"] as? Bool == false {
                    fail("unexpected property \(key)")
                }
            }
        }
        if let array = value as? [Any] {
            if let minItems = schema["minItems"] as? Int, array.count < minItems {
                fail("has \(array.count) items, fewer than \(minItems)")
            }
            if let items = schema["items"] as? [String: Any] {
                for (index, element) in array.enumerated() {
                    errors += validate(element, against: items, path: "\(path)/\(index)")
                }
            }
        }
        return errors
    }

    /// `JSONSerialization` returns booleans as `NSNumber`s of type `c`. The format has no booleans, so the rare
    /// `Int8` that shares the type doesn't matter here.
    private static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return String(cString: number.objCType) == "c"
    }

    private static func number(_ value: Any) -> Double? {
        guard !isBool(value), let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return isBool(value)
        case "number": return number(value) != nil
        case "integer": return number(value).map { $0 == $0.rounded() } ?? false
        case "null": return value is NSNull
        default: return false
        }
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? String, let b = b as? String { return a == b }
        if let a = number(a), let b = number(b) { return a == b }
        return false
    }
}
