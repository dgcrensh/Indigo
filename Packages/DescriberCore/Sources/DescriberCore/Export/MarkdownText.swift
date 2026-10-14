import Foundation

/// Markdown text helpers for the Markdown export: escaping, and heading anchors as GitHub makes them.
public enum MarkdownText {
    /// The characters that would otherwise start emphasis, code, links, HTML or a table cell inside a line.
    private static let specialCharacters: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "|", "#"]

    /// `text` with a backslash before every character Markdown would read as formatting, and line breaks turned into
    /// spaces, so it shows as typed on one line.
    public static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if character.isNewline {
                result.append(" ")
                continue
            }
            if specialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// The anchor GitHub gives a heading reading `text`, before repeats are numbered: lowercased, with punctuation
    /// and symbols dropped and each space turned into `-`. Letters, digits and marks of any script are kept, as are
    /// `-` and `_`.
    public static func anchorBase(_ text: String) -> String {
        var result = ""
        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case " ":
                result.append("-")
            case "-", "_":
                result.unicodeScalars.append(scalar)
            default:
                let properties = scalar.properties
                let isMark = [.nonspacingMark, .spacingMark, .enclosingMark].contains(properties.generalCategory)
                if properties.isAlphabetic || properties.numericType != nil || isMark {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    /// Hands out heading anchors in document order, numbering repeats `-1`, `-2` as GitHub does.
    public struct Anchors {
        private var used: Set<String> = []
        private var repeats: [String: Int] = [:]

        public init() {}

        /// The anchor of the next heading reading `text`.
        public mutating func next(for text: String) -> String {
            let base = MarkdownText.anchorBase(text)
            var anchor = base
            if used.contains(base) {
                var count = repeats[base] ?? 0
                repeat {
                    count += 1
                    anchor = "\(base)-\(count)"
                } while used.contains(anchor)
                repeats[base] = count
            }
            used.insert(anchor)
            return anchor
        }
    }
}
